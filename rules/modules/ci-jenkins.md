## CI (Jenkins)

The helpers in `agents/jenkins/scripts/` read `JENKINS_BASE_URL`,
`JENKINS_USER` and `JENKINS_TOKEN` from the environment. If they are not set,
load them in the same command: `. ~/.config/agent-kit/secrets.env && <helper>`.
Never echo the token or write it into a file in the repository.

1. For a change that has a merge request, revalidate through the request (its
   CI trigger comment or pipeline), so the result stays in the request history.
   Trigger a job directly only for branches without a request or when asked.
2. After triggering, confirm the real build number from the job's `lastBuild`
   API. Never assume it.
3. Check the first lines of the console: the checked-out branch and commit must
   be the ones you intended. A parameter with trailing whitespace or a bad
   refspec can silently fall back to a default branch and still go green.
4. Wait with the helpers instead of polling by hand:
   ```bash
   agents/jenkins/scripts/jenkins_wait_build_register.sh <job> <build>
   agents/jenkins/scripts/jenkins_wait_build.sh        # consumes every pending entry
   ```
5. If a build took its node offline for inspection, bring that exact node back
   before the next run — unless the user reserved it:
   ```bash
   agents/jenkins/scripts/jenkins_node_online_register.sh <node>
   agents/jenkins/scripts/jenkins_node_online.sh
   ```
6. Record the build number, node, coverage and result where the project keeps
   its validation log.
