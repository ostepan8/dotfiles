import copy
import json
import sys
import time
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from govee_api import Device
from govee_hybrid import merge_devices
from govee_lan import (
    LanClient,
    LanDevice,
    LanError,
    UdpTransport,
    build_control_message,
    build_scan_message,
    local_ip,
    parse_scan_response,
    parse_status_response,
    scan_destinations,
)


class FakeTransport:
    def __init__(self, exchanges=()):
        self._exchanges = tuple(exchanges)
        self.exchange_calls = ()
        self.send_calls = ()

    def exchange(self, payload, destinations, timeout, expected=None):
        self.exchange_calls = self.exchange_calls + (
            (payload, tuple(destinations), timeout, expected),
        )
        if not self._exchanges:
            return ()
        current, self._exchanges = self._exchanges[0], self._exchanges[1:]
        return current

    def send(self, payload, destinations):
        self.send_calls = self.send_calls + ((payload, tuple(destinations)),)


def scan_packet(ip="192.0.2.159", sku="H8022", device="AA:BB:CC:DD"):
    return (
        json.dumps(
            {
                "msg": {
                    "cmd": "scan",
                    "data": {"ip": ip, "sku": sku, "device": device},
                }
            }
        ).encode(),
        ip,
    )


class ProtocolTests(unittest.TestCase):
    def test_builds_exact_scan_and_control_envelopes(self):
        self.assertEqual(
            {"msg": {"cmd": "scan", "data": {"account_topic": "reserve"}}},
            json.loads(build_scan_message()),
        )
        cases = (
            ("powerSwitch", 0, {"cmd": "turn", "data": {"value": 0}}),
            ("brightness", 42, {"cmd": "brightness", "data": {"value": 42}}),
            (
                "colorRgb",
                0xFF0080,
                {
                    "cmd": "colorwc",
                    "data": {
                        "color": {"r": 255, "g": 0, "b": 128},
                        "colorTemInKelvin": 0,
                    },
                },
            ),
            (
                "colorTemperatureK",
                2700,
                {
                    "cmd": "colorwc",
                    "data": {
                        "color": {"r": 0, "g": 0, "b": 0},
                        "colorTemInKelvin": 2700,
                    },
                },
            ),
        )
        for instance, value, expected in cases:
            with self.subTest(instance=instance):
                self.assertEqual(
                    {"msg": expected}, json.loads(build_control_message(instance, value))
                )

    def test_rejects_invalid_control_values(self):
        invalid = (
            ("powerSwitch", 2),
            ("brightness", 0),
            ("brightness", 101),
            ("colorRgb", -1),
            ("colorRgb", 0x1000000),
            ("colorTemperatureK", 1999),
            ("colorTemperatureK", 9001),
            ("future", 1),
        )
        for instance, value in invalid:
            with self.subTest(instance=instance, value=value), self.assertRaises(
                LanError
            ):
                build_control_message(instance, value)

    def test_parses_valid_responses_without_mutating_input(self):
        raw, source = scan_packet()
        before = bytes(raw)
        device = parse_scan_response(raw, source)
        self.assertEqual(before, raw)
        self.assertEqual(LanDevice(source, "AA:BB:CC:DD", "H8022"), device)

        status_raw = json.dumps(
            {
                "msg": {
                    "cmd": "devStatus",
                    "data": {
                        "onOff": 1,
                        "brightness": 75,
                        "color": {"r": 1, "g": 2, "b": 3},
                        "colorTemInKelvin": 2700,
                    },
                }
            }
        ).encode()
        status = parse_status_response(status_raw)
        self.assertTrue(status.on)
        self.assertEqual((75, 1, 2, 3, 2700), (
            status.brightness,
            status.color_r,
            status.color_g,
            status.color_b,
            status.color_temp_kelvin,
        ))

    def test_rejects_untrusted_or_malformed_responses(self):
        bad_packets = (
            (b"not-json", "192.0.2.2"),
            (json.dumps({"msg": {"cmd": "other", "data": {}}}).encode(), "192.0.2.2"),
            (scan_packet(ip="8.8.8.8")[0], "8.8.8.8"),
            (scan_packet(sku="bad")[0], "192.0.2.159"),
            (scan_packet(device="")[0], "192.0.2.159"),
        )
        for raw, source in bad_packets:
            with self.subTest(raw=raw, source=source), self.assertRaises(LanError):
                parse_scan_response(raw, source)

        for source in ("127.0.0.1", "169.254.1.2", "0.0.0.0"):
            with self.subTest(source=source), self.assertRaises(LanError):
                parse_scan_response(scan_packet()[0], source)
        with self.assertRaises(LanError):
            parse_scan_response(scan_packet(device="AA:\x1b]8;;bad\x07BB")[0], "192.0.2.2")

    def test_scan_destinations_cover_local_subnet_without_local_host(self):
        destinations = scan_destinations("192.0.2.59")
        self.assertIn(("239.255.255.250", 4001), destinations)
        self.assertIn(("192.0.2.255", 4001), destinations)
        self.assertIn(("192.0.2.159", 4001), destinations)
        self.assertNotIn(("192.0.2.59", 4001), destinations)
        with self.assertRaises(LanError):
            scan_destinations("8.8.8.8")


class LanClientTests(unittest.TestCase):
    def test_discovery_deduplicates_and_ignores_bad_packets(self):
        good = scan_packet()
        transport = FakeTransport(((good, good, (b"bad", "192.0.2.4")),))
        client = LanClient(
            transport=transport,
            local_ip_factory=lambda: "192.0.2.59",
            scan_timeout=0.1,
        )
        self.assertEqual((LanDevice("192.0.2.159", "AA:BB:CC:DD", "H8022"),), client.devices())
        self.assertEqual(1, len(transport.exchange_calls))

    def test_status_times_out_and_control_sends_to_device(self):
        device = LanDevice("192.0.2.159", "AA:BB:CC:DD", "H8022")
        timeout_transport = FakeTransport(((),))
        with self.assertRaisesRegex(LanError, "did not respond"):
            LanClient(transport=timeout_transport).state(device)

        transport = FakeTransport()
        LanClient(transport=transport).control(device, "powerSwitch", 0)
        payload, destinations = transport.send_calls[0]
        self.assertEqual((("192.0.2.159", 4003),), destinations)
        self.assertEqual(0, json.loads(payload)["msg"]["data"]["value"])

    def test_socket_initialization_errors_are_mapped_to_lan_errors(self):
        for operation in (
            local_ip,
            lambda: UdpTransport().send(b"{}", (("192.0.2.2", 4003),)),
            lambda: UdpTransport().exchange(b"{}", (("192.0.2.2", 4001),), 0.1),
        ):
            with self.subTest(operation=operation), patch(
                "govee_lan.socket.socket", side_effect=OSError("denied")
            ), self.assertRaises(LanError):
                operation()

    def test_listener_uses_exclusive_reply_port(self):
        class FakeSocket:
            def __init__(self):
                self.options = ()
                self.bound = None

            def setsockopt(self, level, option, value):
                self.options = self.options + ((level, option, value),)

            def bind(self, address):
                self.bound = address

            def setblocking(self, _enabled):
                return None

            def close(self):
                return None

        fake = FakeSocket()
        with patch("govee_lan.socket.socket", return_value=fake):
            listener = UdpTransport()._listener()
        self.assertIs(fake, listener)
        self.assertEqual(("", 4002), fake.bound)
        self.assertEqual((), fake.options)


class MergeTests(unittest.TestCase):
    def test_merges_cloud_and_lan_by_normalized_id_and_names_lan_only_bed_lamp(self):
        cloud = Device("H8072", "AA:BB:01", "Floor Lamp", "devices.types.light", ())
        lan = (
            LanDevice("192.0.2.40", "aa-bb-01", "H8072"),
            LanDevice("192.0.2.159", "CC:DD:02", "H8022"),
        )
        before = copy.deepcopy(lan)
        merged = merge_devices((cloud,), lan)
        self.assertEqual(before, lan)
        self.assertEqual(("Bedside Lamp", "Floor Lamp"), tuple(item.name for item in merged))
        floor = merged[1]
        self.assertIs(cloud, floor.cloud)
        self.assertEqual("192.0.2.40", floor.lan.ip)
        bedside = merged[0]
        self.assertIsNone(bedside.cloud)
        self.assertEqual("powerSwitch", bedside.capabilities[0].instance)

    def test_rejects_sku_mismatch_and_deduplicates_canonical_cloud_ids(self):
        first = Device("H8072", "AA:BB:01", "Floor Lamp", "devices.types.light", ())
        duplicate = Device("H8072", "aa-bb-01", "Duplicate", "devices.types.light", ())
        wrong_sku = LanDevice("192.0.2.40", "AA:BB:01", "H8022")
        merged = merge_devices((first, duplicate), (wrong_sku,))
        self.assertEqual(1, len(merged))
        self.assertEqual("Floor Lamp", merged[0].name)
        self.assertIsNone(merged[0].lan)


if __name__ == "__main__":
    unittest.main()


class ReceiveReturnsEarlyTest(unittest.TestCase):
    """A one-device question must not wait out the whole timeout window.

    state() asks a single lamp and needs a single reply. The receive loop used
    to drain until the deadline regardless, so every call sat in select() for
    the full DEFAULT_COMMAND_TIMEOUT after the answer had already arrived:
    measured 2.01s per lamp, 8.6s for three, which is why the atlas Lights page
    took nine seconds to load. With expected=1 the same call takes ~0.02s.
    """

    def test_stops_once_the_expected_replies_arrive(self):
        listener = _FakeListener([b"first", b"second"])
        started = time.monotonic()
        with patch("govee_lan.select.select", listener.select):
            got = UdpTransport._receive(listener, 5.0, expected=1)
        self.assertEqual(len(got), 1)
        self.assertLess(time.monotonic() - started, 1.0, "returned late despite a reply")
        self.assertEqual(listener.reads, 1, "read more packets than it was asked for")

    def test_without_an_expected_count_it_drains_until_quiet(self):
        # Discovery cannot know how many lamps exist, so it keeps listening
        # until the socket goes quiet or the window closes.
        listener = _FakeListener([b"one", b"two"])
        with patch("govee_lan.select.select", listener.select):
            got = UdpTransport._receive(listener, 0.5, expected=None)
        self.assertEqual(len(got), 2)


class _FakeListener:
    """Socket stand-in whose select() is only ready while packets remain."""

    def __init__(self, packets):
        self._packets = list(packets)
        self.reads = 0

    def select(self, rlist, _w, _x, _timeout):
        return (list(rlist) if self._packets else [], [], [])

    def recvfrom(self, _size):
        self.reads += 1
        return self._packets.pop(0), ("10.0.0.1", 4002)
