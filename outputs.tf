# kubernetes/base/deployment.yaml
# ─────────────────────────────────────────────────────────────────
# WHAT THIS FILE DOES:
# Defines HOW to run the application in Kubernetes.
# A Deployment ensures the right number of pods (containers) are
# always running and handles rolling updates with zero downtime.
# ─────────────────────────────────────────────────────────────────

apiVersion: apps/v1
kind: Deployment            # Deployment = manages a set of identical pods

metadata:
  name: sample-app
  namespace: sample-app
  labels:
    app: sample-app         # Labels are key-value tags for identifying resources

spec:
  replicas: 2               # Run 2 copies of the pod (high availability)
                            # If one pod crashes, the other keeps serving traffic

  # selector = tells the Deployment which pods it manages
  # Must match template.metadata.labels below
  selector:
    matchLabels:
      app: sample-app

  # strategy = how to update pods when you deploy a new version
  strategy:
    type: RollingUpdate     # Replace pods one at a time (zero downtime)
    rollingUpdate:
      maxSurge: 1           # Can temporarily have 1 EXTRA pod during update
      maxUnavailable: 0     # NEVER have fewer pods than desired (zero downtime)

  # template = the blueprint for each pod
  template:
    metadata:
      labels:
        app: sample-app     # Must match selector.matchLabels above

    spec:
      containers:
        - name: sample-app
          # image = Docker image to run
          # In production, GitHub Actions updates this tag automatically
          image: YOUR_AWS_ACCOUNT.dkr.ecr.ap-south-1.amazonaws.com/sample-app:latest

          ports:
            - containerPort: 8080   # Port the app listens on inside the container

          # resources = CPU and memory limits
          # IMPORTANT: always set limits to prevent one pod starving others
          resources:
            requests:               # Minimum guaranteed resources
              cpu: "100m"           # 100m = 0.1 CPU cores (millicores)
              memory: "128Mi"       # 128 mebibytes RAM
            limits:                 # Maximum allowed resources
              cpu: "500m"           # 0.5 CPU cores
              memory: "512Mi"

          # env = environment variables passed into the container
          env:
            - name: APP_ENV
              value: "dev"
            - name: DB_PASSWORD
              # valueFrom.secretKeyRef = read from Kubernetes Secret (not hardcoded!)
              # Never hardcode passwords in YAML — use Secrets
              valueFrom:
                secretKeyRef:
                  name: app-secrets    # Name of the Secret resource
                  key: db-password     # Key inside the Secret

          # livenessProbe = Kubernetes checks if app is ALIVE
          # If this fails, Kubernetes restarts the pod
          livenessProbe:
            httpGet:
              path: /health          # Call GET /health endpoint
              port: 8080
            initialDelaySeconds: 30  # Wait 30s before first check (app startup time)
            periodSeconds: 10        # Check every 10 seconds

          # readinessProbe = Kubernetes checks if app is READY to serve traffic
          # Pod only gets traffic when this passes
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5

---
# ─────────────────────────────────────────────────────────────────
# Service = gives the Deployment a stable network address
# Pods are temporary and get new IPs — Service IP stays constant
# ─────────────────────────────────────────────────────────────────
apiVersion: v1
kind: Service

metadata:
  name: sample-app
  namespace: sample-app

spec:
  # selector = route traffic to pods with this label
  selector:
    app: sample-app

  ports:
    - protocol: TCP
      port: 80            # External port (what callers use)
      targetPort: 8080    # Internal pod port (forward to here)

  # ClusterIP = only accessible inside the cluster
  # Use LoadBalancer to expose to internet
  type: ClusterIP

---
# ─────────────────────────────────────────────────────────────────
# HorizontalPodAutoscaler = auto-scale pods based on CPU load
# ─────────────────────────────────────────────────────────────────
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler

metadata:
  name: sample-app-hpa
  namespace: sample-app

spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-app       # Which deployment to scale

  minReplicas: 2           # Never go below 2 pods
  maxReplicas: 10          # Never go above 10 pods

  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          # If average CPU across all pods > 70%, add more pods
          averageUtilization: 70
