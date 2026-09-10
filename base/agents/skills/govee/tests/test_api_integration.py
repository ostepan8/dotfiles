import io
import json
import sys
import unittest
from pathlib import Path
from urllib.error import HTTPError, URLError

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from govee_api import ApiError, Device, GoveeClient

DEVICE_RESPONSE = {
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
                    "type": "devices.capabilities.on_off",
                    "instance": "powerSwitch",
                    "parameters": {"dataType": "ENUM"},
                },
                {
                    "type": "devices.capabilities.range",
                    "instance": "brightness",
                    "parameters": {
                        "dataType": "INTEGER",
                        "range": {"min": 1, "max": 100, "precision": 1},
                    },
                },
            ],
        }
    ],
}


class FakeResponse:
    def __init__(self, body, status=200, headers=None):
        self.body = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.status = status
        self.headers = headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self.body


class RecordingOpener:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def __call__(self, request, timeout):
        self.calls = self.calls + [(request, timeout)]
        result = self.responses.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


class GoveeClientIntegrationTests(unittest.TestCase):
    def client(self, responses):
        opener = RecordingOpener(responses)
        client = GoveeClient(
            "literal-test-secret",
            base_url="https://example.test/router/api/v1",
            timeout=7,
            opener=opener,
            request_id_factory=lambda: "fixed-id",
        )
        return client, opener

    def test_discovery_sends_exact_request(self):
        client, opener = self.client([FakeResponse(DEVICE_RESPONSE)])
        devices, warnings = client.devices()
        request, timeout = opener.calls[0]
        self.assertEqual("GET", request.get_method())
        self.assertEqual(
            "https://example.test/router/api/v1/user/devices",
            request.full_url,
        )
        self.assertEqual("literal-test-secret", request.get_header("Govee-api-key"))
        self.assertIsNone(request.data)
        self.assertEqual(7, timeout)
        self.assertEqual("Desk Lamp", devices[0].name)
        self.assertEqual((), warnings)

    def test_state_sends_exact_request_and_returns_capabilities(self):
        state_response = {
            "code": 200,
            "msg": "success",
            "payload": {
                "sku": "H6000",
                "device": "AA:01",
                "capabilities": [
                    {
                        "type": "devices.capabilities.on_off",
                        "instance": "powerSwitch",
                        "state": {"value": 1},
                    }
                ],
            },
        }
        client, opener = self.client([FakeResponse(state_response)])
        device = self._device(client)
        result = client.state(device)
        request, _timeout = opener.calls[0]
        self.assertEqual("POST", request.get_method())
        self.assertEqual(
            "https://example.test/router/api/v1/device/state", request.full_url
        )
        self.assertEqual(
            {
                "requestId": "fixed-id",
                "payload": {"sku": "H6000", "device": "AA:01"},
            },
            json.loads(request.data),
        )
        self.assertEqual("powerSwitch", result[0]["instance"])

    def test_control_sends_discovered_type_and_exact_value(self):
        response = {
            "code": 200,
            "msg": "success",
            "capability": {"state": {"status": "success"}},
        }
        client, opener = self.client([FakeResponse(response)])
        device = self._device(client)
        client.control(device, "brightness", 50)
        request, _timeout = opener.calls[0]
        self.assertEqual("POST", request.get_method())
        self.assertEqual(
            "https://example.test/router/api/v1/device/control", request.full_url
        )
        self.assertEqual(
            {
                "requestId": "fixed-id",
                "payload": {
                    "sku": "H6000",
                    "device": "AA:01",
                    "capability": {
                        "type": "devices.capabilities.range",
                        "instance": "brightness",
                        "value": 50,
                    },
                },
            },
            json.loads(request.data),
        )

    def test_maps_http_network_and_malformed_json_errors_without_key_leak(self):
        errors = (
            (
                HTTPError(
                    "https://example.test",
                    401,
                    "Unauthorized",
                    {},
                    io.BytesIO(b'{"message":"bad key"}'),
                ),
                "API key",
            ),
            (
                HTTPError(
                    "https://example.test",
                    429,
                    "Too Many Requests",
                    {"Retry-After": "30"},
                    io.BytesIO(b"{}"),
                ),
                "30",
            ),
            (
                HTTPError(
                    "https://example.test",
                    503,
                    "Unavailable",
                    {},
                    io.BytesIO(b"{}"),
                ),
                "unavailable",
            ),
            (URLError("dns failure"), "connect"),
        )
        for error, expected in errors:
            with self.subTest(error=error):
                client, _opener = self.client([error])
                with self.assertRaises(ApiError) as raised:
                    client.devices()
                message = str(raised.exception)
                self.assertIn(expected.casefold(), message.casefold())
                self.assertNotIn("literal-test-secret", message)

        client, _opener = self.client([FakeResponse(b"not-json")])
        with self.assertRaisesRegex(ApiError, "JSON"):
            client.devices()

    @staticmethod
    def _device(client):
        devices, _warnings = client.parse_device_response(DEVICE_RESPONSE)
        device = devices[0]
        assert isinstance(device, Device)
        return device


if __name__ == "__main__":
    unittest.main()
