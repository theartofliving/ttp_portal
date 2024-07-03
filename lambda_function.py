import json
import boto3 # type: ignore
from opensearchpy import OpenSearch, RequestsHttpConnection # type: ignore
from requests_aws4auth import AWS4Auth # type: ignore
import os

region = 'ap-south-1'  # e.g. us-west-1
service = 'es'
credentials = boto3.Session().get_credentials()
auth = AWS4Auth(credentials.access_key, credentials.secret_key, region, service, session_token=credentials.token)

host = 'https://vpc-ttpportal-lrysnolxf3dtvnwgchv3xln2py.ap-south-1.es.amazonaws.com'  # OpenSearch domain endpoint
index = 'my-index'
type = '_doc'

s3 = boto3.client('s3')

def lambda_handler(event, context):
    # Get the object from the event and show its content type
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        document = json.loads(content)
        
        opensearch = OpenSearch(
            hosts = [{'host': host, 'port': 443}],
            http_auth = auth,
            use_ssl = True,
            verify_certs = True,
            connection_class = RequestsHttpConnection
        )
        
        opensearch.index(index=index, doc_type=type, body=document)
        
        return {
            'statusCode': 200,
            'body': json.dumps('File processed successfully')
        }
    except Exception as e:
        print(e)
        raise e
