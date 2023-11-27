import boto3
import json
import os
import logging


cognito_records = boto3.client('cognito-idp')
logger = logging.getLogger()
logger.setLevel(logging.INFO)



def lambda_handler(event, context):

    PoolID = os.environ['COGNITO_POOL']

    #For every cloudtrail event extract the sub identifier
    try:
        for record in event['Records']:
            body = json.loads(record["body"])
            #get sub from cloudtrail event to get the username with API call
            userid = body['detail']['additionalEventData']['sub']

    except Exception as e:
        # Send some context about this error to Lambda Logs
        print(e)
        # throw exception, do not handle. Lambda will make message visible again.
        raise e

    #Get username using the sub

    authusers = cognito_records.list_users(
        UserPoolId=PoolID,
        AttributesToGet=['sub',],
        Filter=f"sub^=\"{userid}\"")

    for authuser in authusers['Users']:
        authusername = authuser['Username']
        auth_events = cognito_records.admin_list_user_auth_events(       #Get authentication events for the users, limit to 5
            UserPoolId=PoolID,
            Username=authusername,
            MaxResults=5)
        logging.info("auth events, %s", auth_events) #Send the user events to the logs

    return {
        'statusCode': 200
    }