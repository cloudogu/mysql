@Library([
  'pipe-build-lib',
  'ces-build-lib',
  'dogu-build-lib'
]) _

def pipe = new com.cloudogu.sos.pipebuildlib.DoguPipe(this, [
    doguName             : "mysql",
    shellScripts         : "resources/create-sa.sh resources/remove-sa.sh resources/startup.sh resources/upgrade-notification.sh resources/backup-consumer.sh",
    doBatsTests          : true,
    checkMarkdown        : false,
    dependencies         : ["usermgt", "cas"],
])

pipe.setBuildProperties()
pipe.addDefaultStages()

pipe.insertStageAfter("Verify","End-to-end tests") {
    def ctx = pipe.script

    try {
        def createOutput = ctx.ecoSystem.vagrant.sshOut('sudo cesapp command mysql service-account-create mydogu')
        if (!createOutput.contains('username: mydogu_')) {
            ctx.error "ERROR: expected output to contain username but actually got: ${createOutput}"
        }

        def removeOutput = ctx.ecoSystem.vagrant.sshOut('sudo cesapp command mysql service-account-remove mydogu')
        if (!removeOutput.contains("Deleting service account 'mydogu_")) {
            ctx.error "ERROR: expected output to contain message but actually got: ${removeOutput}"
        }
    } catch (e) {
        ctx.error "ERROR while running cesapp command: Message: ${e}"
    }
}

pipe.run()
