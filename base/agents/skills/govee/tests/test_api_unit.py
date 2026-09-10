import copy
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from govee_api import (
    ApiError,
    Capability,
    Device,
    InputError,
    build_control_payload,
    find_capability,
    pack_rgb,
    parse_color,
    parse_devices,
    select_devices,
    validate_capability_value,
    validate_control_response,
)


def capability(cap_type, instance, parameters=None):
    return Capability(cap_type, instance, parameters or {})


def lamp(name="Desk Lamp", device_id="AA:01", capabilities=None):
    return Device(
        sku="H6000",
        device_id=device_id,
        name=name,
        device_type="devices.types.light",
        capabilities=tuple(
            capabilities
            or (
                capability("devices.capabilities.on_off", "powerSwitch"),
                capability(
                    "devices.capabilities.range",
                    "brightness",
                    {"range": {"min": 1, "max": 100, "precision": 1}},
                ),
                capability("devices.capabilities.color_setting", "colorRgb"),
                capability(
                    "devices.capabilities.color_setting",
                    "colorTemperatureK",
                    {"range": {"min": 2200, "max": 6500, "precision": 1}},
                ),
            )
        ),
    )


class ColorTests(unittest.TestCase):
    def test_accepts_hex_with_or_without_hash_and_rgb(self):
        for value in ("#ff0080", "FF0080", "255,0,128"):
            with self.subTest(value=value):
                self.assertEqual((255, 0, 128), parse_color(value))
        self.assertEqual(16_711_808, pack_rgb((255, 0, 128)))

    def test_rejects_invalid_colors(self):
        invalid = (
            "",
            "#fff",
            "#fffffff",
            "#gg0080",
            "255,0",
            "255,0,0,1",
            "1.5,0,0",
            "-1,0,0",
            "256,0,0",
        )
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(InputError):
                parse_color(value)


class CapabilityTests(unittest.TestCase):
    def test_finds_exact_advertised_instance(self):
        device = lamp()
        found = find_capability(device, "brightness")
        self.assertEqual("devices.capabilities.range", found.type)
        with self.assertRaisesRegex(InputError, "does not support"):
            find_capability(device, "musicMode")

    def test_validates_advertised_range_without_clamping(self):
        brightness = find_capability(lamp(), "brightness")
        self.assertEqual(1, validate_capability_value(brightness, 1))
        self.assertEqual(100, validate_capability_value(brightness, 100))
        for value in (0, 101, 1.5, "50", None):
            with self.subTest(value=value), self.assertRaises(InputError):
                validate_capability_value(brightness, value)

    def test_kelvin_error_includes_device_range(self):
        temperature = find_capability(lamp(), "colorTemperatureK")
        with self.assertRaisesRegex(InputError, "2200.*6500"):
            validate_capability_value(temperature, 2000)

    def test_payload_uses_advertised_capability_and_preserves_inputs(self):
        device = lamp()
        before = copy.deepcopy(device)
        payload = build_control_payload(
            device,
            "brightness",
            42,
            request_id="fixed-request-id",
        )
        self.assertEqual(device, before)
        self.assertEqual(
            {
                "requestId": "fixed-request-id",
                "payload": {
                    "sku": "H6000",
                    "device": "AA:01",
                    "capability": {
                        "type": "devices.capabilities.range",
                        "instance": "brightness",
                        "value": 42,
                    },
                },
            },
            payload,
        )


class DeviceParsingTests(unittest.TestCase):
    def test_parses_documented_device_envelope_and_unknown_capability(self):
        raw = {
            "code": 200,
            "message": "success",
            "data": [
                {
                    "sku": "H6000",
                    "device": "AA:01",
                    "deviceName": "Desk Lamp",
                    "type": "devices.types.light",
                    "capabilities": [
                        {
                            "type": "devices.capabilities.future",
                            "instance": "newThing",
                            "parameters": {"dataType": "INTEGER"},
                        }
                    ],
                }
            ],
        }
        devices, warnings = parse_devices(raw)
        self.assertEqual((), warnings)
        self.assertEqual("newThing", devices[0].capabilities[0].instance)
        self.assertEqual("Desk Lamp", devices[0].name)

    def test_skips_malformed_device_with_warning(self):
        raw = {
            "code": 200,
            "data": [
                {"sku": "H6000", "deviceName": "Broken", "capabilities": []},
                {
                    "sku": "H6000",
                    "device": "AA:01",
                    "deviceName": "Good",
                    "capabilities": [],
                },
            ],
        }
        devices, warnings = parse_devices(raw)
        self.assertEqual(("Good",), tuple(item.name for item in devices))
        self.assertEqual(1, len(warnings))

    def test_rejects_unusable_or_error_envelopes(self):
        for raw in (
            {"code": 401, "message": "invalid key"},
            {"code": 200, "data": "not-a-list"},
            {"code": 200, "data": [{"sku": "H6000"}]},
        ):
            with self.subTest(raw=raw), self.assertRaises(ApiError):
                parse_devices(raw)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.devices = (
            lamp("Desk Lamp", "AA:01"),
            lamp("Floor Lamp", "AA:02"),
        )

    def test_exact_id_and_case_insensitive_exact_name(self):
        self.assertEqual(
            ("AA:02",),
            tuple(item.device_id for item in select_devices(self.devices, ("AA:02",))),
        )
        self.assertEqual(
            ("AA:01",),
            tuple(
                item.device_id for item in select_devices(self.devices, ("desk lamp",))
            ),
        )

    def test_repeated_selectors_preserve_order_and_deduplicate(self):
        selected = select_devices(
            self.devices,
            ("Floor Lamp", "Desk Lamp", "Floor Lamp"),
        )
        self.assertEqual(("AA:02", "AA:01"), tuple(item.device_id for item in selected))

    def test_implicit_selection_requires_exactly_one_compatible_device(self):
        self.assertEqual((self.devices[0],), select_devices(self.devices[:1], ()))
        with self.assertRaisesRegex(InputError, "--device|--all"):
            select_devices(self.devices, ())

    def test_duplicate_and_unknown_names_fail(self):
        duplicates = (lamp("Lamp", "AA:01"), lamp("lamp", "AA:02"))
        with self.assertRaisesRegex(InputError, "AA:01.*AA:02"):
            select_devices(duplicates, ("lamp",))
        with self.assertRaisesRegex(InputError, "No Govee device"):
            select_devices(self.devices, ("Kitchen",))

    def test_all_is_stable_and_cannot_mix_with_selectors(self):
        selected = select_devices(tuple(reversed(self.devices)), (), all_devices=True)
        self.assertEqual(
            ("Desk Lamp", "Floor Lamp"), tuple(item.name for item in selected)
        )
        with self.assertRaises(InputError):
            select_devices(self.devices, ("Desk Lamp",), all_devices=True)


class ControlResponseTests(unittest.TestCase):
    def test_accepts_success(self):
        validate_control_response(
            {
                "code": 200,
                "msg": "success",
                "capability": {"state": {"status": "success"}},
            }
        )

    def test_rejects_top_level_and_nested_failures(self):
        with self.assertRaisesRegex(ApiError, "invalid key"):
            validate_control_response({"code": 401, "message": "invalid key"})
        with self.assertRaisesRegex(ApiError, "Device offline"):
            validate_control_response(
                {
                    "code": 200,
                    "msg": "success",
                    "capability": {
                        "state": {
                            "status": "failure",
                            "errorMsg": "Device offline",
                        }
                    },
                }
            )


if __name__ == "__main__":
    unittest.main()
