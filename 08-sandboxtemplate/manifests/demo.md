envsubst '$ANTHROPIC_MODEL' < 08-sandboxtemplate/manifests/test-template.yaml | kubectl apply -f -

envsubst '$ANTHROPIC_MODEL $TESTING_REPO' < 08-sandboxtemplate/manifests/developer-task.yaml | kubectl apply -f -


envsubst '$ANTHROPIC_MODEL $TESTING_REPO' < 08-sandboxtemplate/manifests/reviewer-routine.yaml | kubectl apply -f -

kubectl create job --from=cronjob/claude-reviewer claude-reviewer-now -n 08-sandboxtemplate
