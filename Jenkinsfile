#!groovy
@Library([
  'github.com/cloudogu/build-lib-wrapper@develop',
  'ces-build-lib', // versioning handled by Global Trusted Pipeline Libraries in Jenkins
  'dogu-build-lib' // versioning handled by Global Trusted Pipeline Libraries in Jenkins
]) _


def postVerifyStage = { ecoSystem ->
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
            error "ERROR while running cesapp command: Message: ${e}"
        }
    }
}

sharedBuildPipeline([
    doguName             : "mysql",
    preBuildAgent        : 'sos',
    buildAgent           : 'sos',
    doguDirectory        : "/dogu",
    namespace            : "official",
    gitUser              : "cesmarvin",
    committerEmail       : "cesmarvin@cloudogu.com",
    gcloudCredentials    : "gcloud-ces-operations-internal-packer",
    sshCredentials       : "jenkins-gcloud-ces-operations-internal",
    backendUser          : "cesmarvin-setup",
    shellScripts         : "resources/create-sa.sh resources/remove-sa.sh resources/startup.sh resources/upgrade-notification.sh resources/backup-consumer.sh",
    doBatsTests          : true,
    checkMarkdown        : false,
    dependencies         : ["usermgt", "cas"],


    // Pass your custom stage here
    postVerifyStage      : postVerifyStage
])
