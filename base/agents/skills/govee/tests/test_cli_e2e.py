import json
import os
import subprocess
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONTROL = Path(__file__).resolve().parents[1] / "scripts" / "control.py"


class ApiHandler(BaseHTTPRequestHandler):
    calls = ()

    def log_message(self, _format, *_args):
        return

    def do_GET(self):
        type(self).calls = type(self).calls + (("GET", self.path, None),)
        self._reply(
            {
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
                            }
                        ],
                    }
                ],
            }
        )

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length))
        type(self).calls = type(self).calls + (("POST", self.path, body),)
        self._reply(
            {
                "code": 200,
                "msg": "success",
                "capability": {"state": {"status": "success"}},
            }
        )

    def _reply(self, body):
        encoded = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


class CliEndToEndTests(unittest.TestCase):
    def setUp(self):
        ApiHandler.calls = ()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), ApiHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_subprocess_discovers_and_controls_lamp(self):
        env = {
            **os.environ,
            "GOVEE_API_KEY": "literal-e2e-secret",
            "GOVEE_LAN_ENABLED": "false",
            "GOVEE_API_BASE": f"http://127.0.0.1:{self.server.server_port}/router/api/v1",
        }
        result = subprocess.run(
            [str(CONTROL), "on", "--device", "Desk Lamp"],
            text=True,
            capture_output=True,
            env=env,
            timeout=5,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotIn("literal-e2e-secret", result.stdout + result.stderr)
        self.assertEqual("GET", ApiHandler.calls[0][0])
        self.assertEqual("/router/api/v1/user/devices", ApiHandler.calls[0][1])
        method, path, body = ApiHandler.calls[1]
        self.assertEqual(("POST", "/router/api/v1/device/control"), (method, path))
        self.assertEqual("H6000", body["payload"]["sku"])
        self.assertEqual("AA:01", body["payload"]["device"])
        self.assertEqual(
            {
                "type": "devices.capabilities.on_off",
                "instance": "powerSwitch",
                "value": 1,
            },
            body["payload"]["capability"],
        )


if __name__ == "__main__":
    unittest.main()
