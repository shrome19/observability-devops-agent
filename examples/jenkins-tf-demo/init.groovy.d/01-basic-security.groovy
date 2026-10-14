// Creates a local admin user and enables basic auth on first boot,
// so you don't have to fish the initial admin password out of the logs.
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

def adminId = System.getenv("JENKINS_ADMIN_ID") ?: "admin"
def adminPw = System.getenv("JENKINS_ADMIN_PASSWORD") ?: "admin"

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
if (hudsonRealm.getAllUsers().find { it.id == adminId } == null) {
    hudsonRealm.createAccount(adminId, adminPw)
    instance.setSecurityRealm(hudsonRealm)

    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)

    instance.save()
    println "--> Created Jenkins admin user '${adminId}'"
}
