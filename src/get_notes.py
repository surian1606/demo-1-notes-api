"""Retrieve all notes for the authenticated user."""
import json
import os

import boto3
from boto3.dynamodb.conditions import Key

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

        result = table.query(
            KeyConditionExpression=Key("userId").eq(user_id)
        )

        return _response(200, {"notes": result["Items"]})

    except Exception as e:
        print(json.dumps({"level": "ERROR", "message": str(e)}))
        return _response(500, {"message": "Internal server error"})
