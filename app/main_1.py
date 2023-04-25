from fastapi import Depends, FastAPI, HTTPException, Form, APIRouter, Query
from fastapi.security import HTTPBasic, HTTPBasicCredentials, OAuth2AuthorizationCodeBearer
from authlib.integrations.starlette_client import OAuth
from fastapi.responses import JSONResponse
from datetime import timedelta
from fastapi_jwt_auth import AuthJWT
from subprocess import Popen, PIPE, STDOUT, check_output
from kubernetes import client,config
from fastapi.security import OAuth2AuthorizationCodeBearer
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from fastapi.security import OAuth2PasswordRequestForm
from fastapi_jwt_auth.exceptions import AuthJWTException
from pydantic import BaseModel
from az.cli import az
import os
import requests


# Azure Login
az('login --tenant 0ae51e19-07c8-4e4b-bb6d-648ee58410f4')
az('account set --subscription f3e03797-77f9-4fe3-b659-cd072361b4fc')
az('aks get-credentials --resource-group lab000167-rg --name lab000167')

# Accessing the config
userdirectory_config = os.path.join(os.path.expanduser('~'),'.kube','config')

# loads the Kubernetes configuration
config.load_kube_config(config_file=userdirectory_config)

# create a Kubernetes API client instance
kube_client = client.CoreV1Api()

app = FastAPI(title="Master Blender API (B/S/H)",
    description="**This app is for creating, deleting, listing and getting info about jenkins instances.**",
    version="0.0.1")
oauth2_scheme = OAuth2AuthorizationCodeBearer(
    authorizationUrl="https://login.microsoftonline.com/0ae51e19-07c8-4e4b-bb6d-648ee58410f4/oauth2/authorize",
    tokenUrl="https://login.microsoftonline.com/0ae51e19-07c8-4e4b-bb6d-648ee58410f4/oauth2/token",
    scopes={"Files.Read": "Files.Read", "profile": "User profile scope"}
)


# # Define your JWT settings
# app.jwt_secret_key = "secret"
# app.jwt_algorithm = "HS256"
# app.jwt_access_token_expires = timedelta(minutes=15)

# # Define your authentication and authorization dependencies
# @app.exception_handler(AuthJWTException)
# async def authjwt_exception_handler(request, exc):
#     return JSONResponse(status_code=exc.status_code, content={"detail": exc.message})

# async def get_current_user(Authorization: str = Depends(AuthJWT)):
#     try:
#         Authorization.jwt_required()
#         username = Authorization.get_jwt_subject()
#         return {"username": username}
#     except AuthJWTException:
#         return None

# # Define your protected endpoints
# @app.get("/protected")
# async def protected_endpoint(current_user = Depends(get_current_user)):
#     if current_user:
#         return {"message": f"Hello, {current_user['username']}!"}
#     else:
#         return {"message": "Unauthorized"}

# @app.post("/login")
# async def login_endpoint(username: str, password: str, Authorization: AuthJWT = Depends()):
#     if username == "myuser" and password == "mypassword":
#         access_token = Authorization.create_access_token(subject=username)
#         return {"access_token": access_token}
#     else:
#         raise HTTPException(status_code=400, detail="Invalid username or password")

# oauth = OAuth()
# oauth.register(
#     name='Fast-api',
#     api_base_url='https://login.microsoftonline.com/0ae51e19-07c8-4e4b-bb6d-648ee58410f4',
#     access_token_url='https://login.microsoftonline.com/0ae51e19-07c8-4e4b-bb6d-648ee58410f4/oauth2/v2.0/token',
#     authorize_url='https://login.microsoftonline.com/0ae51e19-07c8-4e4b-bb6d-648ee58410f4/oauth2/v2.0/authorize',
#     client_id='a57e0c08-b741-430e-8913-1cf42bfae32c',
#     client_secret='TEj8Q~Cukzq_1tfo9SY9JE9yZdiQyhjjjcr1Zdr1',
#     userinfo_endpoint='https://graph.microsoft.com/v1.0/me',
#     scope='openid profile email',
#     # redirect_uri='{redirect_uri}'
# )

# auth = OAuth2AuthorizationCodeBearer(
#     authorizationUrl=f"https://login.microsoftonline.com/0ae51e19-07c8-4e4b-bb6d-648ee58410f4/oauth2/v2.0/authorize",
#     tokenUrl=f"https://login.microsoftonline.com/0ae51e19-07c8-4e4b-bb6d-648ee58410f4/oauth2/v2.0/token",
#     scopes={"openid": "Access user profile", "offline_access": "Refresh token"}
# )

# @app.get("/users/me")
# async def read_users_me(token: str = Depends(get_current_user)):
#     return {"token": token}

# security = HTTPBasic()

# def get_current_user(credentials: HTTPBasicCredentials = Depends(security)):
#     username = credentials.username
#     password = credentials.password
#     # check if the username and password are correct
#     if username != "user" or password != "password":
#         raise HTTPException(
#             status_code=401,
#             detail="Incorrect username or password",
#             headers={"WWW-Authenticate": "Basic"},
#         )
#     return username

# def get_secret(secret_name: str):
#     credential = DefaultAzureCredential()
#     secret_client = SecretClient(vault_url="<your-key-vault-url>", credential=credential)
#     secret_value = secret_client.get_secret(secret_name).value
#     return secret_value
@app.get("/items/")
async def read_items(token: str = Depends(oauth2_scheme)):
    return {"token": token}

@app.get("/")
async def root(token: str = Depends(oauth2_scheme)):
    response = requests.get("https://graph.microsoft.com/v1.0/me", headers={"Authorization": f"Bearer {token}"})
    if response.status_code == 200:
        return {"message": "Hello, World!"}
    else:
        return {"message": "Unauthorized"}



@app.post('/undeploy_jenkins')
async def undeploy_jenkins(current_user: str = Depends(oauth2_scheme)):
    # Run shell script with user input
    username = 'psin1kor'
    password = 'Astroph1@123'
    cmd = f"bash ./scripts/undeploy_jenkins.sh"
    p = Popen(cmd, stdout=PIPE, stdin=PIPE, stderr=STDOUT)
    stdout, stderr = p.communicate(input=b'saurabh\npsjfjfs')

    # Capture the output of the shell script
    if stderr:
        output = f"Error occurred: {stderr.decode()}"
    else:
        output = stdout.decode().split('\n')

    # Send back the response
    return output




@app.post('/deploy_jenkins')
async def deploy_jenkins(name: str, labname:str,current_user: str = Depends(oauth2_scheme)):
    # Run shell script with user input
    username = "saurabh"
    cmd = ['bash', b'./scripts/deploy_jenkins.sh' ]
    p = Popen(cmd, stdout=PIPE, stdin=PIPE, stderr=STDOUT, shell=True)
    stdout, stderr = p.communicate(input=b'saurabh\npsjfjfs')

    # Capture the output of the shell script
    if stderr:
        output = f"Error occurred: {stderr.decode()}"
    else:
        output = stdout.decode().split('\n')

    # Send back the response
    return output




# Api to get the list of pods in specified namespace
@app.get("/pods/{namespace}")
async def list_pods(namespace: str):
    pods = kube_client.list_namespaced_pod(namespace=namespace)
    print(namespace)

    # extracting the pod names
    pod_names = [pod.metadata.name for pod in pods.items]
    return pod_names




# Api to get the pod details
@app.get("/pods/{namespace}/{pod}")
async def get_pod_details(namespace: str, pod: str):
    try:
        pod = kube_client.read_namespaced_pod(name=pod, namespace=namespace)

        # extract the pod details
        pod_details = {
            "name": pod.metadata.name,
            "status": pod.status.phase,
            "pod_ip": pod.status.pod_ip,
            "node_name": pod.spec.node_name,
            "container_names": [c.name for c in pod.spec.containers],
        }
        return pod_details
    except client.rest.ApiException as e:
        if e.status == 404:
            return {"message": f"Pod with name {pod} not found"}
        else:
            return {"message": f"Failed to retrieve pod details: {e}"}
        

















# @app.post("/run_script")
# async def run_script(script_name: str, username:str):
#     try:
#         result = subprocess.run(['bash', f'bash ./scripts/{script_name}.sh {username}'], capture_output=True, text=True)
#         return {"output": result.stdout, "error": result.stderr}
#     except FileNotFoundError:
#         return {"error": f"Script {script_name} not found"}

# @app.post("/run_script/")
# async def run_script(script_name: str,username: str, password: str):
#     # Assuming the script file is in the same directory as this Python file
#     script_file = "./scripts/{script_name}.sh"
    
#     # Split the input arguments into a list
#     input_args_list = [username, password]
    
#     # Run the shell script with the input arguments
#     output = subprocess.check_output([script_file, *input_args_list], universal_newlines=True)

#     return {"output": output}


# @app.post("/create_jenkins_instance")
# async def create_jenkins_instance():
#     try:
#         # Run the shell command to create the Jenkins instance using Helm charts
#         subprocess.check_output("helm install jenkinss-1 -n jenkins -f values.yaml jenkinsci/jenkins", shell=True)
#     except subprocess.CalledProcessError as e:
#         # If the shell command returns a non-zero exit code, raise an HTTPException with a 500 status code
#         raise HTTPException(status_code=500, detail=f"Failed to create Jenkins instance: {e.output}")
#     else:
#         # If the command succeeds, return a success message
#         return {"message": "Jenkins instance created successfully."}
    




    
    

    
# Api to delete the specified pod
# @app.delete("/delete_pod/{namespace}/{pod_name}")
# async def delete_pod(namespace: str, pod_name: str):
#     try:
#         # delete the pod in the specific namespace
#         kube_client.delete_namespaced_pod(name=pod_name, namespace=namespace)
#         return {"message": f"Deleted pod {pod_name}"}
#     except Exception as e:
#         return {"error": str(e)}
    
# @app.post("/run_script/")
# async def run_script(user: User):
#     script = subprocess.Popen(['bash', './scripts/undeploy_jenkins.sh',("psin1kor","Astrophysics1@123"),], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
#     script.stdin.write(bytes(user.first_name + '\n', 'utf-8'))
#     script.stdin.write(bytes(user.name1 + ' ' + user.name2 + ' ' + user.name3 + '\n', 'utf-8'))
#     output, error = script.communicate()
#     if error:
#         raise HTTPException(status_code=500, detail=error.decode('utf-8'))
#     return {"output": output.decode('utf-8')}

