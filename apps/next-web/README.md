# next-web

Next.js web application for the travel marketplace. It is configured for a
standalone production build so it can run as a small Node.js container in EKS.

## Getting Started

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

Health checks are served from `/api/health`.

## Build

```bash
npm run build
```

## Container

After applying `infra/environments/dev`, push an image to the ECR repository
from the Terraform output:

```bash
cd apps/next-web
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
docker build -t <next_web_ecr_repository_url>:latest .
docker push <next_web_ecr_repository_url>:latest
```

The dev Terraform deployment uses `var.next_web_image_tag`, which defaults to
`latest`.

## EKS

The dev environment creates the Kubernetes `Deployment`, `Service`, `HPA`, and
ALB-backed `Ingress` for this app.
