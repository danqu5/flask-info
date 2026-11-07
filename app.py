from flask import Flask, jsonify
import requests
from datetime import datetime

app = Flask(__name__)

IMDS_BASE = "http://169.254.169.254/latest"
NOT_EC2 = "not running on an EC2 instance"


def imds_get(path):
    """Read instance metadata using IMDSv2 (session token), which the
    instance enforces. Falls back to an untokened IMDSv1 request so the
    app still works on hosts where IMDSv1 is allowed."""
    headers = {}
    try:
        token = requests.put(
            f"{IMDS_BASE}/api/token",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "300"},
            timeout=1,
        )
        token.raise_for_status()
        headers["X-aws-ec2-metadata-token"] = token.text
    except Exception:
        pass

    try:
        response = requests.get(f"{IMDS_BASE}/meta-data/{path}", headers=headers, timeout=1)
        response.raise_for_status()
        return response.text
    except Exception:
        return NOT_EC2


@app.route("/info")
def info():
    return jsonify({
        "instance_id": imds_get("instance-id"),
        "availability_zone": imds_get("placement/availability-zone"),
        "timestamp": datetime.utcnow().isoformat() + "Z"
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
