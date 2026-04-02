"""Retrieve a single note by ID for the authenticated user."""
import json
import os

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def _get_user_id(event):
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
        note_id = event["pathParameters"]["noteId"]

        result = table.get_item(Key={"userId": user_id, "noteId": note_id})

        item = result.get("Item")
        if not item:
            return _response(404, {"message": "Note not found"})

        return _response(200, item)

    except Exception as e:
        print(json.dumps({"level": "ERROR", "message": str(e)}))
        return _response(500, {"message": "Internal server error"})
