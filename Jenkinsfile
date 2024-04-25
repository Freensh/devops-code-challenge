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
    }
        
}
