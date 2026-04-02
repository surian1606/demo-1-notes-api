"""Create a new note for the authenticated user."""
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

# Best practice: initialize client outside handler for environment reuse (Module 7)
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def _get_user_id(event):
    """Extract userId from Cognito authorizer claims."""
    return event["requestContext"]["authorizer"]["claims"]["sub"]


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps(body),
    }


def handler(event, context):
    try:
        user_id = _get_user_id(event)
        body = json.loads(event.get("body") or "{}")

        if not body.get("title"):
            return _response(400, {"message": "title is required"})

        note_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        item = {
            "userId": user_id,
            "noteId": note_id,
            "title": body["title"],
            "content": body.get("content", ""),
            "createdAt": now,
            "updatedAt": now,
        }

        table.put_item(Item=item)

        return _response(201, item)

    except Exception as e:
        print(json.dumps({"level": "ERROR", "message": str(e)}))
        return _response(500, {"message": "Internal server error"})
