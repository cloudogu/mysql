#!groovy
@Library(['github.com/cloudogu/ces-build-lib@4.2.0', 'github.com/cloudogu/dogu-build-lib@v3.2.0'])
import com.cloudogu.ces.cesbuildlib.*
import com.cloudogu.ces.dogubuildlib.*

timestamps {
    node('docker') {
        stage('Checkout') {
            checkout scm
        }

        stage('Lint') {
            lintDockerfile()
            shellCheck("resources/create-sa.sh resources/remove-sa.sh resources/startup.sh resources/upgrade-notification.sh resources/backup-consumer.sh")
        }

        stage('Shell tests') {
            def bats_base_image = "bats/bats"
            def bats_custom_image = "cloudogu/bats"
            def bats_tag = "1.2.1"

            def batsImage = docker.build("${bats_custom_image}:${bats_tag}", "--build-arg=BATS_BASE_IMAGE=${bats_base_image} --build-arg=BATS_TAG=${bats_tag} ./batsTests")
            try {
                sh "mkdir -p target"
                sh "mkdir -p testdir"

                batsContainer = batsImage.inside("--entrypoint='' -v ${WORKSPACE}:/workspace -v ${WORKSPACE}/testdir:/usr/share/webapps") {
                    sh "make unit-test-shell-ci"
                }
            } finally {
                junit allowEmptyResults: true, testResults: 'target/shell_test_reports/*.xml'
            }
        }
    }

    node('vagrant') {

        Git git = new Git(this, 'cesmarvin')
        git.committerName = 'cesmarvin'
        git.committerEmail = 'cesmarvin@cloudogu.com'
        String doguDirectory = '/dogu'
        GitFlow gitflow = new GitFlow(this, git)
        GitHub github = new GitHub(this, git)
        Changelog changelog = new Changelog(this)

        properties([
                // Keep only the last x builds to preserve space
                buildDiscarder(logRotator(numToKeepStr: '10')),
                // Don't run concurrent builds for a branch, because they use the same workspace directory
                disableConcurrentBuilds(),
                parameters([
                    booleanParam(defaultValue: true, description: 'Enables cypress to record video of the integration tests.', name: 'EnableVideoRecording'),
                    booleanParam(defaultValue: true, description: 'Enables cypress to take screenshots of failing integration tests.', name: 'EnableScreenshotRecording'),
                    choice(name: 'TrivySeverityLevels', choices: [TrivySeverityLevel.CRITICAL, TrivySeverityLevel.HIGH_AND_ABOVE, TrivySeverityLevel.MEDIUM_AND_ABOVE, TrivySeverityLevel.ALL], description: 'The levels to scan with trivy', defaultValue: TrivySeverityLevel.CRITICAL),
                    choice(name: 'TrivyStrategy', choices: [TrivyScanStrategy.UNSTABLE, TrivyScanStrategy.FAIL, TrivyScanStrategy.IGNORE], description: 'Define whether the build should be unstable, fail or whether the error should be ignored if any vulnerability was found.', defaultValue: TrivyScanStrategy.UNSTABLE),
                ])
        ])

        EcoSystem ecoSystem = new EcoSystem(this, 'gcloud-ces-operations-internal-packer', 'jenkins-gcloud-ces-operations-internal')

        try {
            stage('Provision') {
                // change namespace to prerelease_namespace if in develop-branch
                if (gitflow.isPreReleaseBranch()) {
                    sh "make prerelease_namespace"
                }
                ecoSystem.provision(doguDirectory)
            }

            stage('Setup') {
                ecoSystem.loginBackend('cesmarvin-setup')
                ecoSystem.setup()
            }

            stage('Wait for dependencies') {
                timeout(15) {
                    ecoSystem.waitForDogu('cas')
                    ecoSystem.waitForDogu('usermgt')
                }
            }

            stage('Build') {
                ecoSystem.build(doguDirectory)
            }

            stage('Trivy scan') {
                ecoSystem.copyDoguImageToJenkinsWorker("/dogu")
                Trivy trivy = new Trivy(this)
                trivy.scanDogu(".", params.TrivySeverityLevels, params.TrivyStrategy)
                trivy.saveFormattedTrivyReport(TrivyScanFormat.TABLE)
                trivy.saveFormattedTrivyReport(TrivyScanFormat.JSON)
                trivy.saveFormattedTrivyReport(TrivyScanFormat.HTML)
            }

            stage('Verify') {
                ecoSystem.verify(doguDirectory)
            }

            stage('End-to-end tests') {
                try {
                    def createOutput = ecoSystem.vagrant.sshOut('sudo cesapp command mysql service-account-create mydogu')
                    if (!createOutput.contains('username: mydogu_')) {
                        error "ERROR: expected output to contain username but actually got: ${createOutput}"
                    }

                    def removeOutput = ecoSystem.vagrant.sshOut('sudo cesapp command mysql service-account-remove mydogu')
                    if (!removeOutput.contains("Deleting service account 'mydogu_")) {
                        error "ERROR: expected output to contain message but actually got: ${removeOutput}"
                    }
                } catch (e) {
                    // catch
                    error "ERROR while running cesapp command: Message: ${e}"
                }
            }

            if (gitflow.isReleaseBranch()) {
                String releaseVersion = git.getSimpleBranchName()

                stage('Finish Release') {
                    gitflow.finishRelease(releaseVersion, "main")
                }

                stage('Push Dogu to registry') {
                    ecoSystem.push(doguDirectory)
                }

                stage('Add Github-Release') {
                    github.createReleaseWithChangelog(releaseVersion, changelog, "main")
                }
            } else if (gitflow.isPreReleaseBranch()) {
                 // push to registry in prerelease_namespace
                 stage('Push Prerelease Dogu to registry') {
                     ecoSystem.pushPreRelease("/dogu")
                 }
             }

        } finally {
            stage('Clean') {
                ecoSystem.destroy()
            }
        }
    }
}