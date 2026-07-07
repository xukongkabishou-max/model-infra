cat <<'EOF' | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: runc
handler: runc
EOF

kubectl patch deploy metax-gpu-scheduler \
  -n metax-operator \
  --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/runtimeClassName",
      "value": "runc"
    }
  ]'

kubectl rollout status deploy/metax-gpu-scheduler -n metax-operator --timeout=120s
kubectl get pod -n metax-operator -l app=metax-gpu-scheduler -o wide