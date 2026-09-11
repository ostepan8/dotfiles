import io
import json
import os
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from control import (
    ACCOUNT_HOME,
    VAULT_BINARY,
    VAULT_HOME,
    VAULT_PATH,
    _validated_vault_binary,
    load_vault_key,
    main,
    save_vault_key,
)
from govee_api import ApiError, Capability, Device, InputError
from govee_lan import LanDevice, LanError, LanStatus


def cap(cap_type, instance, parameters=None):
    return Capability(cap_type, instance, parameters or {})


def test_lamp(name, device_id, capabilities=None):
    return Device(
        "H6000",
        device_id,
        name,
        "devices.types.light",
        tuple(
            capabilities
            or (
                cap("devices.capabilities.on_off", "powerSwitch"),
                cap(
                    "devices.capabilities.range",
                    "brightness",
                    {"range": {"min": 1, "max": 100}},
                ),
                cap("devices.capabilities.color_setting", "colorRgb"),
                cap(
                    "devices.capabilities.color_setting",
                    "colorTemperatureK",
                    {"range": {"min": 2200, "max": 6500}},
                ),
            )
        ),
    )


class FakeClient:
    def __init__(self, devices, *, failures=None):
        self._devices = tuple(devices)
        self._failures = frozenset(failures or ())
        self.controls = ()
        self.state_calls = ()

    def devices(self):
        return self._devices, ()

    def control(self, device, instance, value):
        self.controls = self.controls + ((device.device_id, instance, value),)
        if device.device_id in self._failures:
            raise ApiError("Device offline")

    def state(self, device) -> tuple[dict[str, object], ...]:
        self.state_calls = self.state_calls + (device.device_id,)
        return (
            {
                "type": "devices.capabilities.online",
                "instance": "online",
                "state": {"value": True},
            },
            {
                "type": "devices.capabilities.on_off",
                "instance": "powerSwitch",
                "state": {"value": 1},
            },
            {
                "type": "devices.capabilities.range",
                "instance": "brightness",
                "state": {"value": 75},
            },
        )


class FakeLanClient:
    def __init__(
        self, devices=(), *, discovery_error=None, state_error=None, control_error=None
    ):
        self._devices = tuple(devices)
        self._discovery_error = discovery_error
        self._state_error = state_error
        self._control_error = control_error
        self.controls = ()
        self.state_calls = ()

    def devices(self):
        if self._discovery_error:
            raise self._discovery_error
        return self._devices

    def control(self, device, instance, value):
        if self._control_error:
            raise self._control_error
        self.controls = self.controls + ((device.device_id, instance, value),)

    def state(self, device):
        self.state_calls = self.state_calls + (device.device_id,)
        if self._state_error:
            raise self._state_error
        return LanStatus(True, 60, 255, 128, 0, 2700)


def run_cli(argv, fake, env=None):
    stdout, stderr = io.StringIO(), io.StringIO()
    effective_env = {
        "GOVEE_API_KEY": "test-key",
        "GOVEE_LAN_ENABLED": "false",
        **(env or {}),
    }
    exit_code = main(
        argv,
        env=effective_env,
        stdout=stdout,
        stderr=stderr,
        client_factory=lambda *_args, **_kwargs: fake,
    )
    return exit_code, stdout.getvalue(), stderr.getvalue()


class CliFlowTests(unittest.TestCase):
    def setUp(self):
        self.desk = test_lamp("Desk Lamp", "AA:01")
        self.floor = test_lamp("Floor Lamp", "AA:02")

    def test_devices_prints_stable_capability_summary(self):
        fake = FakeClient((self.floor, self.desk))
        code, stdout, stderr = run_cli(["devices"], fake)
        self.assertEqual(0, code)
        self.assertLess(stdout.index("Desk Lamp"), stdout.index("Floor Lamp"))
        self.assertIn("power brightness color", stdout)
        self.assertEqual("", stderr)

    def test_power_brightness_and_color_commands(self):
        cases = (
            (["on", "--device", "Desk Lamp"], "powerSwitch", 1),
            (["off", "--device", "Desk Lamp"], "powerSwitch", 0),
            (["brightness", "50", "--device", "Desk Lamp"], "brightness", 50),
            (["color", "#ff0080", "--device", "Desk Lamp"], "colorRgb", 16_711_808),
            (
                ["temperature", "2700", "--device", "Desk Lamp"],
                "colorTemperatureK",
                2700,
            ),
        )
        for argv, instance, value in cases:
            with self.subTest(argv=argv):
                fake = FakeClient((self.desk,))
                code, stdout, stderr = run_cli(argv, fake)
                self.assertEqual(0, code)
                self.assertEqual((("AA:01", instance, value),), fake.controls)
                self.assertIn("Desk Lamp", stdout)
                self.assertEqual("", stderr)

    def test_missing_key_bad_input_and_unsupported_capability_do_not_control(self):
        no_color = test_lamp(
            "Plain Lamp",
            "AA:03",
            (cap("devices.capabilities.on_off", "powerSwitch"),),
        )
        cases = (
            (["on", "--device", "Desk Lamp"], {}, self.desk),
            (["color", "#bad", "--device", "Desk Lamp"], None, self.desk),
            (["color", "#ffffff", "--device", "Plain Lamp"], None, no_color),
        )
        for argv, explicit_env, device in cases:
            with self.subTest(argv=argv, env=explicit_env):
                fake = FakeClient((device,))
                env = (
                    explicit_env
                    if explicit_env is not None
                    else {"GOVEE_API_KEY": "test-key"}
                )
                stdout, stderr = io.StringIO(), io.StringIO()
                code = main(
                    argv,
                    env={"GOVEE_LAN_ENABLED": "false", **env},
                    stdout=stdout,
                    stderr=stderr,
                    client_factory=lambda *_args, _fake=fake, **_kwargs: _fake,
                    secret_loader=lambda: None,
                )
                self.assertEqual(2, code)
                self.assertEqual((), fake.controls)
                self.assertTrue(stderr.getvalue())

    def test_ambiguous_target_does_not_control(self):
        fake = FakeClient((test_lamp("Lamp", "AA:01"), test_lamp("lamp", "AA:02")))
        code, _stdout, stderr = run_cli(["on", "--device", "lamp"], fake)
        self.assertEqual(2, code)
        self.assertIn("AA:01", stderr)
        self.assertEqual((), fake.controls)

    def test_explicit_non_light_target_does_not_control(self):
        heater = Device(
            "H7000",
            "HEAT:01",
            "Space Heater",
            "devices.types.heater",
            (cap("devices.capabilities.on_off", "powerSwitch"),),
        )
        fake = FakeClient((heater,))
        code, _stdout, stderr = run_cli(["on", "--device", "Space Heater"], fake)
        self.assertEqual(2, code)
        self.assertIn("light", stderr.casefold())
        self.assertEqual((), fake.controls)

    def test_all_continues_after_device_refusal_and_returns_failure(self):
        fake = FakeClient((self.floor, self.desk), failures=("AA:01",))
        code, stdout, stderr = run_cli(["off", "--all"], fake)
        self.assertEqual(1, code)
        self.assertEqual(
            (("AA:01", "powerSwitch", 0), ("AA:02", "powerSwitch", 0)),
            fake.controls,
        )
        self.assertIn("Floor Lamp", stdout)
        self.assertIn("Device offline", stderr)

    def test_status_reads_state_without_control(self):
        fake = FakeClient((self.desk,))
        code, stdout, stderr = run_cli(["status", "--device", "Desk Lamp"], fake)
        self.assertEqual(0, code)
        self.assertEqual(("AA:01",), fake.state_calls)
        self.assertEqual((), fake.controls)
        self.assertIn("online=yes", stdout)
        self.assertIn("power=on", stdout)
        self.assertIn("brightness=75%", stdout)
        self.assertEqual("", stderr)

    def test_status_json_includes_stable_device_identity_and_inactive_temperature(self):
        class JSONFake(FakeClient):
            def state(self, device) -> tuple[dict[str, object], ...]:
                self.state_calls = self.state_calls + (device.device_id,)
                return (
                    {"instance": "online", "state": {"value": True}},
                    {"instance": "powerSwitch", "state": {"value": 1}},
                    {"instance": "brightness", "state": {"value": 75}},
                    {"instance": "colorRgb", "state": {"value": 0x12ABEF}},
                    {"instance": "colorTemperatureK", "state": {"value": 0}},
                )

        fake = JSONFake((self.desk,))
        code, stdout, stderr = run_cli(["status", "--all", "--json"], fake)
        self.assertEqual(0, code, stderr)
        self.assertEqual(
            [{
                "id": "AA:01", "name": "Desk Lamp", "online": True,
                "power": "on", "brightness": 75, "color": "#12abef",
                "temperature": 0,
            }],
            json.loads(stdout),
        )

    def test_status_json_rejects_missing_or_malformed_required_state(self):
        class InvalidStateFake(FakeClient):
            def __init__(self, devices, state):
                super().__init__(devices)
                self._state = state

            def state(self, device) -> tuple[dict[str, object], ...]:
                self.state_calls = self.state_calls + (device.device_id,)
                return self._state

        invalid_states = (
            (),
            (
                {"instance": "online", "state": {"value": "false"}},
                {"instance": "powerSwitch", "state": {"value": 2}},
            ),
        )
        for state in invalid_states:
            with self.subTest(state=state):
                code, stdout, stderr = run_cli(
                    ["status", "--all", "--json"],
                    InvalidStateFake((self.desk,), state),
                )
                self.assertEqual(1, code)
                self.assertEqual([], json.loads(stdout))
                self.assertIn("valid online state", stderr)

    def test_merged_devices_and_lan_only_lamp_route_through_lan(self):
        cloud = FakeClient((self.floor, self.desk))
        lan = FakeLanClient(
            (
                LanDevice("192.0.2.40", "AA:01", "H6000"),
                LanDevice("192.0.2.159", "BED:01", "H8022"),
            )
        )
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            ["off", "--all"],
            env={"GOVEE_API_KEY": "test-key"},
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: cloud,
            lan_client_factory=lambda: lan,
        )
        self.assertEqual(0, code, stderr.getvalue())
        self.assertEqual(
            (("BED:01", "powerSwitch", 0), ("AA:01", "powerSwitch", 0)),
            lan.controls,
        )
        self.assertEqual(("AA:02", "powerSwitch", 0), cloud.controls[0])
        self.assertEqual(3, len(lan.controls) + len(cloud.controls))
        self.assertIn("Bedside Lamp", stdout.getvalue())

    def test_lan_only_status_works_without_api_key_or_cloud_client(self):
        lan = FakeLanClient((LanDevice("192.0.2.159", "BED:01", "H8022"),))

        def unexpected_cloud(*_args, **_kwargs):
            raise AssertionError("cloud client must not be created")

        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            ["status", "--device", "Bedside Lamp"],
            env={},
            stdout=stdout,
            stderr=stderr,
            client_factory=unexpected_cloud,
            lan_client_factory=lambda: lan,
            secret_loader=lambda: None,
        )
        self.assertEqual(0, code, stderr.getvalue())
        self.assertEqual(("BED:01",), lan.state_calls)
        self.assertIn("power=on", stdout.getvalue())
        self.assertIn("brightness=60%", stdout.getvalue())
        self.assertIn("Cloud discovery unavailable", stderr.getvalue())

    def test_lan_failure_warns_and_cloud_still_controls(self):
        cloud = FakeClient((self.desk,))
        lan = FakeLanClient(discovery_error=LanError("permission denied"))
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            ["on", "--device", "Desk Lamp"],
            env={"GOVEE_API_KEY": "test-key"},
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: cloud,
            lan_client_factory=lambda: lan,
        )
        self.assertEqual(0, code)
        self.assertEqual((("AA:01", "powerSwitch", 1),), cloud.controls)
        self.assertIn("LAN discovery failed", stderr.getvalue())

    def test_merged_device_falls_back_to_cloud_after_definite_lan_failure(self):
        cloud = FakeClient((self.desk,))
        lan = FakeLanClient(
            (LanDevice("192.0.2.40", "AA:01", "H6000"),),
            control_error=LanError("send denied"),
            state_error=LanError("timed out"),
        )
        for argv in (
            ["on", "--device", "Desk Lamp"],
            ["status", "--device", "Desk Lamp"],
        ):
            with self.subTest(argv=argv):
                cloud.controls = ()
                cloud.state_calls = ()
                stdout, stderr = io.StringIO(), io.StringIO()
                code = main(
                    argv,
                    env={"GOVEE_API_KEY": "test-key"},
                    stdout=stdout,
                    stderr=stderr,
                    client_factory=lambda *_args, **_kwargs: cloud,
                    lan_client_factory=lambda: lan,
                )
                self.assertEqual(0, code, stderr.getvalue())
                self.assertIn("used cloud", stderr.getvalue())
        self.assertEqual(("AA:01",), cloud.state_calls)

    def test_all_deduplicates_equivalent_cloud_ids_before_lan_write(self):
        duplicate = test_lamp("Duplicate", "aa-01")
        cloud = FakeClient((self.desk, duplicate))
        lan = FakeLanClient((LanDevice("192.0.2.40", "AA:01", "H6000"),))
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            ["off", "--all"],
            env={"GOVEE_API_KEY": "test-key"},
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: cloud,
            lan_client_factory=lambda: lan,
        )
        self.assertEqual(0, code, stderr.getvalue())
        self.assertEqual(1, len(lan.controls))
        self.assertEqual((), cloud.controls)

    def test_invalid_lan_setting_fails_before_network_access(self):
        cloud = FakeClient((self.desk,))
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            ["devices"],
            env={"GOVEE_API_KEY": "test-key", "GOVEE_LAN_ENABLED": "maybe"},
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: cloud,
            lan_client_factory=lambda: (_ for _ in ()).throw(
                AssertionError("LAN client must not be created")
            ),
        )
        self.assertEqual(2, code)
        self.assertIn("true or false", stderr.getvalue())

    def test_setup_verifies_and_saves_prompted_key(self):
        fake = FakeClient((self.desk,))

        class Saver:
            values = ()

            def __call__(self, value):
                self.values = self.values + (value,)

        saver = Saver()
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            patch("control._validated_vault_binary", return_value="/safe/vault"),
            patch("control.getpass.getpass", return_value="prompted-secret"),
        ):
            code = main(
                ["setup"],
                env={},
                stdout=stdout,
                stderr=stderr,
                client_factory=lambda *_args, **_kwargs: fake,
                key_saver=saver,
            )
        self.assertEqual(0, code)
        self.assertEqual(("prompted-secret",), saver.values)
        self.assertIn("found 1 device", stdout.getvalue())
        self.assertNotIn("prompted-secret", stdout.getvalue() + stderr.getvalue())

    def test_setup_rejects_empty_key_and_untrusted_api_base(self):
        fake = FakeClient((self.desk,))
        with (
            patch("control._validated_vault_binary", return_value="/safe/vault"),
            patch("control.getpass.getpass", return_value=""),
        ):
            code, stdout, stderr = self._main(["setup"], fake, {})
        self.assertEqual(2, code)
        self.assertEqual("", stdout)
        self.assertIn("cannot be empty", stderr)

        code, _stdout, stderr = self._main(
            ["devices"],
            fake,
            {
                "GOVEE_API_KEY": "test-key",
                "GOVEE_API_BASE": "https://attacker.example",
            },
        )
        self.assertEqual(2, code)
        self.assertIn("official API", stderr)

    def test_vault_reads_and_writes_without_putting_secret_in_argv(self):
        completed = subprocess.CompletedProcess([], 0, stdout="saved-key\n", stderr="")
        with (
            patch("control._validated_vault_binary", return_value="/safe/vault"),
            patch("control.subprocess.run", return_value=completed) as run,
        ):
            self.assertEqual("saved-key", load_vault_key())
            save_vault_key("fake-secret")
        read_args = run.call_args_list[0].args[0]
        write_args = run.call_args_list[1].args[0]
        self.assertEqual(["get", "GOVEE_API_KEY"], read_args[-2:])
        self.assertEqual(["store", "GOVEE_API_KEY", "--replace"], write_args[-3:])
        self.assertNotIn("fake-secret", write_args)
        self.assertEqual("fake-secret\n", run.call_args_list[1].kwargs["input"])
        for call in run.call_args_list:
            environment = call.kwargs["env"]
            self.assertEqual({"HOME", "VAULT_HOME", "PATH", "LANG"}, set(environment))
            self.assertEqual(str(ACCOUNT_HOME), environment["HOME"])
            self.assertEqual(str(VAULT_HOME), environment["VAULT_HOME"])
            self.assertNotIn("PYTHONPATH", environment)
            self.assertNotIn("VAULT_CALLER", environment)
            self.assertEqual(VAULT_PATH, environment["PATH"])
            self.assertEqual(sys.executable, call.args[0][0])
            self.assertEqual("-I", call.args[0][1])

        with (
            patch(
                "control._validated_vault_binary",
                side_effect=InputError("vault unavailable"),
            ),
            patch("control.subprocess.run") as run,
        ):
            with self.assertRaisesRegex(InputError, "vault unavailable"):
                load_vault_key()
            with self.assertRaisesRegex(InputError, "vault unavailable"):
                save_vault_key("fake-secret")
        run.assert_not_called()

    def test_vault_failures_are_sanitized(self):
        missing = subprocess.CompletedProcess([], 1, stdout="", stderr="no such secret")
        failed = subprocess.CompletedProcess(
            [], 1, stdout="fake-secret", stderr="fake-secret"
        )
        with (
            patch("control._validated_vault_binary", return_value="/safe/vault"),
            patch("control.subprocess.run", return_value=missing),
        ):
            self.assertIsNone(load_vault_key())
        with (
            patch("control._validated_vault_binary", return_value="/safe/vault"),
            patch("control.subprocess.run", return_value=failed),
        ):
            for operation in (load_vault_key, lambda: save_vault_key("fake-secret")):
                with self.assertRaises(InputError) as raised:
                    operation()
                self.assertNotIn("fake-secret", str(raised.exception))

    def test_vault_binary_requires_safe_owner_permissions(self):
        safe_directory = SimpleNamespace(
            st_mode=stat.S_IFDIR | 0o700, st_uid=os.getuid()
        )
        safe_file = SimpleNamespace(st_mode=stat.S_IFREG | 0o700, st_uid=os.getuid())
        with patch(
            "control.os.lstat",
            side_effect=(
                safe_directory,
                safe_directory,
                safe_directory,
                safe_file,
                safe_file,
            ),
        ):
            self.assertEqual(VAULT_BINARY, _validated_vault_binary())

        unsafe = (
            SimpleNamespace(st_mode=stat.S_IFLNK | 0o700, st_uid=os.getuid()),
            SimpleNamespace(st_mode=stat.S_IFREG | 0o700, st_uid=os.getuid() + 1),
            SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=os.getuid()),
            SimpleNamespace(st_mode=stat.S_IFREG | 0o720, st_uid=os.getuid()),
        )
        for metadata in unsafe:
            with (
                patch(
                    "control.os.lstat",
                    side_effect=(
                        safe_directory,
                        safe_directory,
                        safe_directory,
                        metadata,
                        safe_file,
                    ),
                ),
                self.assertRaisesRegex(InputError, "unsafe ownership"),
            ):
                _validated_vault_binary()

        with (
            patch(
                "control.os.lstat",
                side_effect=(
                    safe_directory,
                    safe_directory,
                    safe_directory,
                    safe_file,
                    unsafe[0],
                ),
            ),
            self.assertRaisesRegex(InputError, "unsafe ownership"),
        ):
            _validated_vault_binary()

        unsafe_directory = SimpleNamespace(
            st_mode=stat.S_IFDIR | 0o720, st_uid=os.getuid()
        )
        for index in range(3):
            parents = [safe_directory, safe_directory, safe_directory]
            parents[index] = unsafe_directory
            with (
                patch("control.os.lstat", side_effect=parents),
                self.assertRaisesRegex(InputError, "unsafe parent"),
            ):
                _validated_vault_binary()

    def test_loopback_base_never_receives_a_vault_secret(self):
        fake = FakeClient((self.desk,))
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            ["devices"],
            env={
                "GOVEE_API_BASE": "http://127.0.0.1:9999/router/api/v1",
                "GOVEE_LAN_ENABLED": "false",
            },
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: fake,
            secret_loader=lambda: "real-vault-secret",
        )
        self.assertEqual(2, code)
        self.assertIn("GOVEE_API_KEY", stderr.getvalue())

    def test_setup_fails_before_prompt_when_vault_is_unavailable(self):
        fake = FakeClient((self.desk,))
        with (
            patch(
                "control._validated_vault_binary",
                side_effect=InputError("Local secrets vault is unavailable"),
            ),
            patch("control.getpass.getpass") as prompt,
        ):
            code, _stdout, stderr = self._main(["setup"], fake, {})
        self.assertEqual(2, code)
        self.assertIn("vault is unavailable", stderr)
        prompt.assert_not_called()

    @staticmethod
    def _main(argv, fake, env):
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            argv,
            env={"GOVEE_LAN_ENABLED": "false", **env},
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: fake,
            secret_loader=lambda: None,
        )
        return code, stdout.getvalue(), stderr.getvalue()


if __name__ == "__main__":
    unittest.main()
