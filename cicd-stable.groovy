node('linux') {
  stage ('Poll') {
    checkout([
      $class: 'GitSCM', branches: [[name: '*/main']], extensions: [],
      userRemoteConfigs: [[url: 'https://github.com/zopencommunity/cryptographyport.git']]])
  }
  stage('Build') {
    build job: 'Port-Pipeline', parameters: [
      string(name: 'PORT_GITHUB_REPO', value: 'https://github.com/zopencommunity/cryptographyport.git'),
      string(name: 'PORT_DESCRIPTION', value: 'Cryptographic recipes and primitives for Python (Rust extension, cross-compiled for z/OS)'),
      string(name: 'BUILD_LINE', value: 'STABLE'),
      booleanParam(name: 'PUBLISH_PYTHON_WHEEL', value: true)
    ]
  }
}
