"""Update an existing note for the authenticated user."""
import json
import os
from datetime import datetime, timezone

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
        body = json.loads(event.get("body") or "{}")

        if not body.get("title") and not body.get("content"):
            return _response(400, {"message": "title or content is required"})

        # Build update expression dynamically
        update_parts = []
        expr_names = {}
        expr_values = {":updatedAt": datetime.now(timezone.utc).isoformat()}

        if body.get("title"):
            update_parts.append("#t = :title")
            expr_names["#t"] = "title"
            expr_values[":title"] = body["title"]

        if body.get("content") is not None:
            update_parts.append("#c = :content")
            expr_names["#c"] = "content"
            expr_values[":content"] = body["content"]

        update_parts.append("updatedAt = :updatedAt")

        update_kwargs = {
            "Key": {"userId": user_id, "noteId": note_id},
            "UpdateExpression": "SET " + ", ".join(update_parts),
            "ExpressionAttributeValues": expr_values,
            "ReturnValues": "ALL_NEW",
            "ConditionExpression": "attribute_exists(userId)",
        }
        if expr_names:
            update_kwargs["ExpressionAttributeNames"] = expr_names

        result = table.update_item(**update_kwargs)

        return _response(200, result["Attributes"])

    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        return _response(404, {"message": "Note not found"})
    except Exception as e:
        print(json.dumps({"level": "ERROR", "message": str(e)}))
        return _response(500, {"message": "Internal server error"})
