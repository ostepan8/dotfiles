"""Minimal native macOS Keychain access that keeps secrets out of argv."""

from __future__ import annotations

import ctypes
from typing import Any

ERR_SEC_ITEM_NOT_FOUND = -25300
ERR_SEC_DUPLICATE_ITEM = -25299
MAX_UINT32 = (1 << 32) - 1
SECURITY_FRAMEWORK = "/System/Library/Frameworks/Security.framework/Security"
CORE_FOUNDATION_FRAMEWORK = (
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
)


class KeychainError(RuntimeError):
    """Raised when macOS Keychain Services refuses an operation."""


def _frameworks() -> tuple[Any, Any]:
    try:
        security = ctypes.CDLL(SECURITY_FRAMEWORK)
        core = ctypes.CDLL(CORE_FOUNDATION_FRAMEWORK)
    except OSError as error:
        raise KeychainError("macOS Keychain frameworks are unavailable") from error
    _configure_functions(security, core)
    return security, core


def _configure_functions(security: Any, core: Any) -> None:
    security.SecKeychainFindGenericPassword.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_char_p,
        ctypes.c_uint32,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_void_p),
        ctypes.POINTER(ctypes.c_void_p),
    ]
    security.SecKeychainFindGenericPassword.restype = ctypes.c_int32
    security.SecKeychainItemFreeContent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    security.SecKeychainItemFreeContent.restype = ctypes.c_int32
    security.SecKeychainItemModifyAttributesAndData.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_void_p,
    ]
    security.SecKeychainItemModifyAttributesAndData.restype = ctypes.c_int32
    security.SecKeychainAddGenericPassword.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_char_p,
        ctypes.c_uint32,
        ctypes.c_char_p,
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_void_p),
    ]
    security.SecKeychainAddGenericPassword.restype = ctypes.c_int32
    core.CFRelease.argtypes = [ctypes.c_void_p]
    core.CFRelease.restype = None


def _identifier(value: str, label: str) -> bytes:
    encoded = value.encode("utf-8")
    if not encoded:
        raise ValueError(f"{label} must not be empty")
    if len(encoded) > MAX_UINT32:
        raise ValueError(f"{label} is too long")
    return encoded


def _secret_buffer(password: str) -> bytearray:
    encoded = bytearray(password, "utf-8")
    if not encoded:
        raise ValueError("password must not be empty")
    if len(encoded) > MAX_UINT32:
        raise ValueError("password is too long")
    return encoded


def _find_item(
    security: Any,
    service: bytes,
    account: bytes,
    *,
    include_password: bool,
) -> tuple[int, int, int | None, int | None]:
    password_length = ctypes.c_uint32()
    password_data = ctypes.c_void_p()
    item = ctypes.c_void_p()
    length_pointer = ctypes.byref(password_length) if include_password else None
    data_pointer = ctypes.byref(password_data) if include_password else None
    status = security.SecKeychainFindGenericPassword(
        None,
        len(service),
        service,
        len(account),
        account,
        length_pointer,
        data_pointer,
        ctypes.byref(item),
    )
    return status, password_length.value, password_data.value, item.value


def load_password(service: str, account: str) -> str | None:
    service_bytes = _identifier(service, "service")
    account_bytes = _identifier(account, "account")
    security, core = _frameworks()
    status, length, password_data, item = _find_item(
        security, service_bytes, account_bytes, include_password=True
    )
    if status == ERR_SEC_ITEM_NOT_FOUND:
        return None
    if status != 0:
        if item is not None:
            core.CFRelease(item)
        raise KeychainError(f"macOS Keychain read failed with status {status}")
    if password_data is None:
        if item is not None:
            core.CFRelease(item)
        raise KeychainError("macOS Keychain returned empty credential data")
    free_status = 0
    try:
        password = ctypes.string_at(password_data, length).decode("utf-8")
    except UnicodeDecodeError as error:
        raise KeychainError(
            "macOS Keychain returned invalid credential data"
        ) from error
    finally:
        free_status = security.SecKeychainItemFreeContent(None, password_data)
        if item is not None:
            core.CFRelease(item)
    if free_status != 0:
        raise KeychainError(
            f"macOS Keychain buffer release failed with status {free_status}"
        )
    return password


def _modify_password(
    security: Any, core: Any, item: int, length: int, pointer: ctypes.c_void_p
) -> int:
    try:
        return security.SecKeychainItemModifyAttributesAndData(
            item, None, length, pointer
        )
    finally:
        core.CFRelease(item)


def _add_password(
    security: Any,
    service: bytes,
    account: bytes,
    length: int,
    pointer: ctypes.c_void_p,
) -> int:
    return security.SecKeychainAddGenericPassword(
        None,
        len(service),
        service,
        len(account),
        account,
        length,
        pointer,
        None,
    )


def save_password(service: str, account: str, password: str) -> None:
    service_bytes = _identifier(service, "service")
    account_bytes = _identifier(account, "account")
    security, core = _frameworks()
    secret = _secret_buffer(password)
    buffer = (ctypes.c_ubyte * len(secret)).from_buffer(secret)
    pointer = ctypes.cast(buffer, ctypes.c_void_p)
    try:
        status, _length, _data, item = _find_item(
            security, service_bytes, account_bytes, include_password=False
        )
        if status == 0 and item is not None:
            result = _modify_password(security, core, item, len(secret), pointer)
        elif status == ERR_SEC_ITEM_NOT_FOUND:
            result = _add_password(
                security, service_bytes, account_bytes, len(secret), pointer
            )
            if result == ERR_SEC_DUPLICATE_ITEM:
                retry_status, _length, _data, retry_item = _find_item(
                    security, service_bytes, account_bytes, include_password=False
                )
                if retry_status != 0 or retry_item is None:
                    raise KeychainError(
                        f"macOS Keychain retry failed with status {retry_status}"
                    )
                result = _modify_password(
                    security, core, retry_item, len(secret), pointer
                )
        else:
            raise KeychainError(f"macOS Keychain lookup failed with status {status}")
    finally:
        ctypes.memset(ctypes.addressof(buffer), 0, len(secret))
    if result != 0:
        raise KeychainError(f"macOS Keychain write failed with status {result}")
