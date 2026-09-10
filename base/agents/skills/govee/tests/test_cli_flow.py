import io
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from control import load_keychain_key, main, save_keychain_key
from govee_api import ApiError, Capability, Device, InputError


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

    def state(self, device):
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


def run_cli(argv, fake, env=None):
    stdout, stderr = io.StringIO(), io.StringIO()
    effective_env = {"GOVEE_API_KEY": "test-key", **(env or {})}
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
                    env=env,
                    stdout=stdout,
                    stderr=stderr,
                    client_factory=lambda *_args, _fake=fake, **_kwargs: _fake,
                    keychain_loader=lambda: None,
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

    def test_setup_verifies_and_saves_prompted_key(self):
        fake = FakeClient((self.desk,))

        class Saver:
            values = ()

            def __call__(self, value):
                self.values = self.values + (value,)

        saver = Saver()
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            patch("control.sys.platform", "darwin"),
            patch("control.os.path.isfile", return_value=True),
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
            patch("control.sys.platform", "darwin"),
            patch("control.os.path.isfile", return_value=True),
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

    def test_keychain_uses_system_binary_and_fails_cleanly_off_macos(self):
        completed = subprocess.CompletedProcess([], 0, stdout="saved-key\n", stderr="")
        with (
            patch("control.sys.platform", "darwin"),
            patch("control.os.path.isfile", return_value=True),
            patch("control.subprocess.run", return_value=completed) as run,
        ):
            self.assertEqual("saved-key", load_keychain_key())
        self.assertEqual("/usr/bin/security", run.call_args.args[0][0])

        with (
            patch("control.sys.platform", "linux"),
            patch("control.subprocess.run") as run,
        ):
            self.assertIsNone(load_keychain_key())
            with self.assertRaisesRegex(InputError, "GOVEE_API_KEY"):
                save_keychain_key("secret")
        run.assert_not_called()

    def test_loopback_base_never_receives_a_keychain_secret(self):
        fake = FakeClient((self.desk,))
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            ["devices"],
            env={"GOVEE_API_BASE": "http://127.0.0.1:9999/router/api/v1"},
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: fake,
            keychain_loader=lambda: "real-keychain-secret",
        )
        self.assertEqual(2, code)
        self.assertIn("GOVEE_API_KEY", stderr.getvalue())

    def test_setup_fails_before_prompt_when_keychain_is_unavailable(self):
        fake = FakeClient((self.desk,))
        with (
            patch("control.sys.platform", "linux"),
            patch("control.getpass.getpass") as prompt,
        ):
            code, _stdout, stderr = self._main(["setup"], fake, {})
        self.assertEqual(2, code)
        self.assertIn("GOVEE_API_KEY", stderr)
        prompt.assert_not_called()

    @staticmethod
    def _main(argv, fake, env):
        stdout, stderr = io.StringIO(), io.StringIO()
        code = main(
            argv,
            env=env,
            stdout=stdout,
            stderr=stderr,
            client_factory=lambda *_args, **_kwargs: fake,
            keychain_loader=lambda: None,
        )
        return code, stdout.getvalue(), stderr.getvalue()


if __name__ == "__main__":
    unittest.main()
