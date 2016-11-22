// CI runs the exact same container definition developers use locally, so "works on my machine"
// and "works in CI" are the same statement.
pipeline {
  agent { label 'docker' }
  options {
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
    disableConcurrentBuilds(abortPrevious: true)
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }
  environment {
    DEVBOX_YES = '1'
    NO_COLOR = '1'
    // Unique project name per build so parallel jobs on one agent don't collide.
    DEVBOX_NAME_SUFFIX = "${env.BUILD_TAG}".toLowerCase().replaceAll('[^a-z0-9]+', '-')
  }
  stages {
    stage('Lint devbox') {
      steps {
        sh 'shellcheck -x bin/devbox lib/*.sh || true'
        sh 'bash tests/run.sh'
      }
    }
    stage('Environment') {
      steps {
        sh '''
          echo "DEVBOX_NAME=ci-${DEVBOX_NAME_SUFFIX}" > .devbox.local
          bin/devbox doctor || true
          bin/devbox up
        '''
      }
    }
    stage('Test') {
      steps {
        sh 'bin/devbox test | tee test-output.log'
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml, **/junit*.xml'
          archiveArtifacts artifacts: 'test-output.log', allowEmptyArchive: true
        }
      }
    }
  }
  post {
    always {
      sh 'bin/devbox clean || true'
    }
    failure {
      echo 'Build failed; container logs:'
      sh 'bin/devbox status || true'
    }
  }
}
