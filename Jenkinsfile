// Declarative pipeline that mirrors .github/workflows/devsecops-pipeline.yml, stage for stage and in the same order.
//
// Stays faithful to the Actions workflow, including its gaps:
//   * Trivy is REPORT-ONLY (exit code 0), ZAP is REPORT-ONLY, Dependency-Check has no failure threshold.
//   * Secret scanning (Gitleaks) FAILS the build on a finding.
//   * "Deploy to Staging" and "Security Policy Gate" are PLACEHOLDERS that only print a message.
//   * Deploy runs only on main, as in Actions. Set FORCE_STAGING to exercise the placeholder stages from another branch.
//
// Scanners run as official container images through the Docker CLI, so Jenkins itself only needs docker.
// --volumes-from <this container> makes the workspace visible to them at the same path (the container id is kept in env.JC).

def scan(String image, String args, String extra = '') {
    // Runs `image` with the workspace mounted at the same path as in this container.
    sh """
        docker run --rm --volumes-from ${env.JC} -w "\$WORKSPACE" ${extra} ${image} ${args}
    """
}

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 90, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    parameters {
        booleanParam(name: 'FORCE_STAGING', defaultValue: false,
                     description: 'Run the (placeholder) staging deploy and policy gate even when not on main')
    }

    environment {
        IMAGE_NAME = 'devsecops-demo-app'
        IMAGE_REF  = "devsecops-demo-app:${env.BUILD_NUMBER}"
        NET        = "devsecops-net-${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script { env.JC = sh(returnStdout: true, script: 'hostname').trim() }
                sh 'mkdir -p reports && git log --oneline -3 && docker version --format "docker {{.Client.Version}} / daemon {{.Server.Version}}"'
            }
        }

        stage('Secret Scanning') {
            steps {
                // Blocking: any finding fails the build (--exit-code 1).
                script {
                    scan('zricethezav/gitleaks:latest',
                         'detect --source . --redact --no-banner --exit-code 1 --report-format sarif --report-path reports/gitleaks.sarif')
                }
            }
        }

        stage('Security Scans') {
            parallel {
                stage('SAST (Semgrep)') {
                    steps {
                        // Report-only here: no --error flag, so findings are written to the SARIF file but do not fail the stage.
                        script {
                            scan('semgrep/semgrep:latest',
                                 'semgrep scan --config p/owasp-top-ten --config p/security-audit --metrics=off --sarif --output reports/semgrep.sarif .')
                        }
                    }
                }
                stage('SCA (Dependency-Check)') {
                    steps {
                        // Report-only: no failure threshold. Dependency-Check needs a free NVD API key to download its
                        // vulnerability database. Without one it cannot run, so the stage is marked UNSTABLE (visible in
                        // the build) instead of breaking the whole pipeline, and NO SCA report is produced on that run.
                        // The database is cached in a named volume.
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                            script {
                                def key = env.NVD_API_KEY ?: ''
                                if (!key) {
                                    echo 'NVD_API_KEY is not set: Dependency-Check may fail to update its database and produce no report.'
                                }
                                scan('owasp/dependency-check:latest',
                                     "--scan . --project devsecops-demo-app --format SARIF --format HTML --out reports --disableAssembly" + (key ? ' --nvdApiKey "$NVD_API_KEY"' : ''),
                                     '-v depcheck-data:/usr/share/dependency-check/data' + (key ? ' -e NVD_API_KEY' : ''))
                            }
                        }
                    }
                }
            }
        }

        stage('Build & Container Image') {
            steps {
                // The "app" is a placeholder page packaged as a WAR, exactly like the Actions workflow.
                script {
                    scan('eclipse-temurin:17-jdk',
                         '''sh -c 'mkdir -p build/webapp && echo "<html><body>DevSecOps demo app placeholder</body></html>" > build/webapp/index.html && jar cf build/app.war -C build/webapp .' ''')
                }
                sh 'docker build -t "$IMAGE_REF" .'
            }
        }

        stage('Container Image Scanning (Trivy)') {
            steps {
                // Report-only: --exit-code 0, so CRITICAL/HIGH findings are reported but never fail the build.
                script {
                    scan('aquasec/trivy:latest',
                         'image --exit-code 0 --severity CRITICAL,HIGH --format sarif --output reports/trivy.sarif "$IMAGE_REF"',
                         '-v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache')
                }
            }
        }

        stage('DAST (OWASP ZAP baseline)') {
            steps {
                // Report-only: a failing ZAP step is logged but does not fail the build.
                script {
                    sh '''
                        docker network create "$NET"
                        docker run -d --name "app-$BUILD_NUMBER" --network "$NET" --network-alias app "$IMAGE_REF"
                        for i in $(seq 1 45); do
                          if docker run --rm --network "$NET" curlimages/curl -sf http://app:8080/ -o /dev/null; then echo "app is up"; break; fi
                          sleep 2
                        done
                    '''
                    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                        sh """
                            docker run --rm --network "\$NET" --volumes-from ${env.JC} --user root \\
                              -e WORKSPACE="\$WORKSPACE" -e ZAP_TARGET=http://app:8080/ \\
                              --entrypoint sh ghcr.io/zaproxy/zaproxy:stable "\$WORKSPACE/jenkins/scripts/zap-baseline.sh"
                        """
                    }
                }
            }
        }

        stage('Deploy to Staging (placeholder)') {
            when { anyOf { expression { env.GIT_BRANCH?.endsWith('/main') }; expression { params.FORCE_STAGING } } }
            steps {
                sh 'echo "Deploy container image $IMAGE_REF to staging (placeholder: nothing is deployed)"'
            }
        }

        stage('Security Policy Gate (placeholder)') {
            when { anyOf { expression { env.GIT_BRANCH?.endsWith('/main') }; expression { params.FORCE_STAGING } } }
            steps {
                sh 'echo "Gate passed - no critical findings blocked the pipeline (placeholder: no scan result is read)"'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
            sh '''
                docker rm -f "app-$BUILD_NUMBER" >/dev/null 2>&1 || true
                docker network rm "$NET" >/dev/null 2>&1 || true
            '''
        }
    }
}
