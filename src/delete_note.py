"""Delete a note for the authenticated user."""
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

        table.delete_item(
            Key={"userId": user_id, "noteId": note_id},
            ConditionExpression="attribute_exists(userId)",
        )

        return _response(200, {"message": "Note deleted"})

    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        return _response(404, {"message": "Note not found"})
    except Exception as e:
        print(json.dumps({"level": "ERROR", "message": str(e)}))
        return _response(500, {"message": "Internal server error"})
