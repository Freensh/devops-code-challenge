pipeline {
    agent any

    stages {

        stage ('Destroy the infrastructure'){
            steps{
                sh '''
                terraform destroy -auto-approve
                cd ecr
                terraform destroy -auto-approve
                '''
            }
        }    
        
        stage ('Initialising the terraform code to Launch the frontend and the backend app'){
            steps{
                
                sh 'terraform init'
            }
        }

    }
}
