from fastapi import Depends, FastAPI, HTTPException, Form, APIRouter, Query
from fastapi.security import HTTPBasic, HTTPBasicCredentials, OAuth2AuthorizationCodeBearer
from authlib.integrations.starlette_client import OAuth
from subprocess import Popen, PIPE, STDOUT, check_output
from kubernetes import client,config
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from az.cli import az
import os


# Azure Login
az('login --tenant 0ae51e19-07c8-4e4b-bb6d-648ee58410f4')
az('account set --subscription e61c9c1e-1f3b-4a27-bd84-1631b0c60c12')
az('aks get-credentials --resource-group jwf1kor --name testing')

# Accessing the config
userdirectory_config = os.path.join(os.path.expanduser('~'),'.kube','config')

# loads the Kubernetes configuration
config.load_kube_config(config_file=userdirectory_config)

# create a Kubernetes API client instance
kube_client = client.CoreV1Api()

app = FastAPI(title="Master Blender API (B/S/H) - First prototype",
    description="**This app is for creating, deleting, listing and getting info about jenkins instances.**",
    version="0.0.1")


security = HTTPBasic()

def get_current_user(credentials: HTTPBasicCredentials = Depends(security)):
    username = credentials.username
    password = credentials.password
    # check if the username and password are correct
    if username != "user" or password != "password":
        raise HTTPException(
            status_code=401,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return username

@app.get("/")
async def root(current_user: str = Depends(get_current_user)):
    return {"message": "Hello {current_user}"}



@app.post('/undeploy_jenkins')
async def undeploy_jenkins(current_user: str = Depends(get_current_user)):
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
async def deploy_jenkins(name: str, labname:str,current_user: str = Depends(get_current_user)):
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

