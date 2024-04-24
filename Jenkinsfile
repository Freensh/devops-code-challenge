pipeline {
    agent any

    stages {

        stage ('Destroy the infrastructure'){
            steps{
                sh '''
                cd ecr
                terraform destroy -auto-approve
                '''
            }
        }    

        stage ('Build and push backend and frontend images to ECR'){
            steps {
                sh '''
                cd ecr
                terraform init
                terraform apply -auto-approve
                '''
            }
        }
        
        stage ('Initialising the terraform code to Launch the frontend and the backend app'){
            steps{
                
                sh 'terraform init'
            }
        }

        stage ('Deploying the app to ECS'){
            steps{
                sh 'terraform apply --auto-approve'
            }
        }
    }
}
