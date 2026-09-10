import ctypes
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from keychain import KeychainError, load_password, save_password


class FakeFunction:
    def __init__(self, implementation):
        self.implementation = implementation
        self.calls = ()
        self.argtypes = None
        self.restype = None

    def __call__(self, *args):
        self.calls = (*self.calls, args)
        return self.implementation(*args)


class FakeSecurity:
    def __init__(
        self,
        *,
        find_status=0,
        password=b"saved-key",
        add_status=0,
        modify_status=0,
    ):
        statuses = find_status if isinstance(find_status, tuple) else (find_status,)
        self.find_statuses = statuses
        self.password = (
            ctypes.create_string_buffer(password) if password is not None else None
        )
        self.written_values = ()

        def find(*args):
            call_index = len(self.SecKeychainFindGenericPassword.calls) - 1
            status = self.find_statuses[min(call_index, len(self.find_statuses) - 1)]
            if status == 0:
                if args[5] is not None:
                    ctypes.cast(args[5], ctypes.POINTER(ctypes.c_uint32))[0] = len(
                        password or b""
                    )
                    if self.password is not None:
                        ctypes.cast(args[6], ctypes.POINTER(ctypes.c_void_p))[0] = (
                            ctypes.cast(self.password, ctypes.c_void_p)
                        )
                ctypes.cast(args[7], ctypes.POINTER(ctypes.c_void_p))[0] = 123
            return status

        def capture(length, pointer):
            self.written_values = (
                *self.written_values,
                ctypes.string_at(pointer, length),
            )
            return 0

        def capture_modify(*args):
            capture(args[2], args[3])
            return modify_status

        def capture_add(*args):
            capture(args[5], args[6])
            return add_status

        self.SecKeychainFindGenericPassword = FakeFunction(find)
        self.SecKeychainItemFreeContent = FakeFunction(lambda *_args: 0)
        self.SecKeychainItemModifyAttributesAndData = FakeFunction(capture_modify)
        self.SecKeychainAddGenericPassword = FakeFunction(capture_add)


class FakeCoreFoundation:
    def __init__(self):
        self.CFRelease = FakeFunction(lambda *_args: None)


class KeychainTests(unittest.TestCase):
    def test_load_reads_and_releases_native_keychain_data(self):
        security, core = FakeSecurity(), FakeCoreFoundation()
        with patch("keychain._frameworks", return_value=(security, core)):
            self.assertEqual("saved-key", load_password("service", "account"))
        self.assertEqual(1, len(security.SecKeychainItemFreeContent.calls))
        self.assertEqual(1, len(core.CFRelease.calls))

    def test_load_returns_none_only_for_missing_item(self):
        security, core = FakeSecurity(find_status=-25300), FakeCoreFoundation()
        with patch("keychain._frameworks", return_value=(security, core)):
            self.assertIsNone(load_password("service", "account"))
        security = FakeSecurity(find_status=-25293)
        with (
            patch("keychain._frameworks", return_value=(security, core)),
            self.assertRaises(KeychainError),
        ):
            load_password("service", "account")

    def test_load_releases_item_when_success_has_no_password_data(self):
        security, core = FakeSecurity(password=None), FakeCoreFoundation()
        with (
            patch("keychain._frameworks", return_value=(security, core)),
            self.assertRaisesRegex(KeychainError, "empty credential"),
        ):
            load_password("service", "account")
        self.assertEqual(1, len(core.CFRelease.calls))

    def test_save_updates_existing_item_without_a_subprocess(self):
        security, core = FakeSecurity(), FakeCoreFoundation()
        with patch("keychain._frameworks", return_value=(security, core)):
            save_password("service", "account", "new-secret")
        modify = security.SecKeychainItemModifyAttributesAndData
        self.assertEqual(1, len(modify.calls))
        self.assertEqual(0, len(security.SecKeychainAddGenericPassword.calls))
        self.assertEqual(1, len(core.CFRelease.calls))
        self.assertEqual((b"new-secret",), security.written_values)

    def test_save_adds_missing_item_and_rejects_empty_values(self):
        security, core = FakeSecurity(find_status=-25300), FakeCoreFoundation()
        with patch("keychain._frameworks", return_value=(security, core)):
            save_password("service", "account", "new-secret")
        self.assertEqual(1, len(security.SecKeychainAddGenericPassword.calls))
        self.assertEqual((b"new-secret",), security.written_values)
        for values in (
            ("", "account", "secret"),
            ("service", "", "secret"),
            ("service", "account", ""),
        ):
            with self.assertRaises(ValueError):
                save_password(*values)

    def test_save_handles_duplicate_add_race(self):
        security = FakeSecurity(
            find_status=(-25300, 0), add_status=-25299, password=None
        )
        core = FakeCoreFoundation()
        with patch("keychain._frameworks", return_value=(security, core)):
            save_password("service", "account", "new-secret")
        self.assertEqual(2, len(security.SecKeychainFindGenericPassword.calls))
        self.assertEqual(1, len(security.SecKeychainItemModifyAttributesAndData.calls))
        self.assertEqual(1, len(core.CFRelease.calls))

    def test_framework_failure_happens_before_secret_buffer_allocation(self):
        with (
            patch("keychain._frameworks", side_effect=KeychainError("unavailable")),
            patch("keychain._secret_buffer") as secret_buffer,
            self.assertRaisesRegex(KeychainError, "unavailable"),
        ):
            save_password("service", "account", "new-secret")
        secret_buffer.assert_not_called()


if __name__ == "__main__":
    unittest.main()
