@Library([
  'pipe-build-lib',
  'ces-build-lib',
  'dogu-build-lib@bug/fix_verify_error'
]) _

def pipe = new com.cloudogu.sos.pipebuildlib.DoguPipe(this, [
    doguName             : 'mysql',
    shellScripts         : '''
                            resources/create-sa.sh
                            resources/remove-sa.sh
                            resources/startup.sh
                            resources/upgrade-notification.sh
                            resources/backup-consumer.sh
                            ''',
    doBatsTests          : true,
    checkMarkdown        : false,
    dependencies         : ['usermgt', 'cas'],
])

pipe.setBuildProperties()
pipe.addDefaultStages()
com.cloudogu.ces.dogubuildlib.EcoSystem ecoSystem = pipe.ecoSystem

pipe.insertStageBefore('MN-Verify', 'Patch Goss-Test for MN') {
  sh "sed -i 's/btrfs/ext4/g' ./spec/goss/goss.yaml"
}

pipe.insertStageAfter('Verify', 'End-to-end tests') {
    def script = pipe.script

    try {
        def createOutput = ecoSystem.vagrant.sshOut('sudo cesapp command mysql service-account-create mydogu')
        if (!createOutput.contains('username: mydogu_')) {
            script.error "ERROR: expected output to contain username but actually got: ${createOutput}"
        }

        def removeOutput = ecoSystem.vagrant.sshOut('sudo cesapp command mysql service-account-remove mydogu')
        if (!removeOutput.contains("Deleting service account 'mydogu_")) {
            script.error "ERROR: expected output to contain message but actually got: ${removeOutput}"
        }
    } catch (e) {
        script.error "ERROR while running cesapp command: Message: ${e}"
    }
}

pipe.run()
