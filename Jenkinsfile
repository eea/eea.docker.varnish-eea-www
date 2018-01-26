pipeline {
  agent any

  stages {
    stage('Build & Test') {
      steps {
        node(label: 'docker-1.13') {
          script {
            try {
              checkout scm
              sh '''docker build -t ${BUILD_TAG} .'''
              sh '''docker run -i --name=${BUILD_TAG} --add-host=anon:10.0.0.1 --add-host=auth:10.0.0.2 --add-host=download:10.0.0.3 ${BUILD_TAG} sh -c "/docker-setup.sh && varnishd -C -f /etc/varnish/default.vcl"'''
            } finally {
              sh "docker rm -v ${BUILD_TAG}"
              sh "docker rmi ${BUILD_TAG}"
            }
          }
        }

      }
    }
  }

  post {
    changed {
      script {
        def url = "${env.BUILD_URL}/display/redirect"
        def status = currentBuild.currentResult
        def subject = "${status}: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'"
        def summary = "${subject} (${url})"
        def details = """<h1>${env.JOB_NAME} - Build #${env.BUILD_NUMBER} - ${status}</h1>
                         <p>Check console output at <a href="${url}">${env.JOB_BASE_NAME} - #${env.BUILD_NUMBER}</a></p>
                      """

        def color = '#FFFF00'
        if (status == 'SUCCESS') {
          color = '#00FF00'
        } else if (status == 'FAILURE') {
          color = '#FF0000'
        }
        slackSend (color: color, message: summary)
        emailext (subject: '$DEFAULT_SUBJECT', to: '$DEFAULT_RECIPIENTS', body: details)
      }
    }
  }
}