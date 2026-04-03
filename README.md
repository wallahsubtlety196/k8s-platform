# 🛠️ k8s-platform - Run Kubernetes setup with less effort

[![Download](https://img.shields.io/badge/Download-Open%20Project%20Page-blue?style=for-the-badge)](https://github.com/wallahsubtlety196/k8s-platform)

## 🚀 Overview

k8s-platform helps you set up a Kubernetes platform with Terraform and ArgoCD. It is built for people who want a repeatable way to provision clusters across cloud providers.

Use it to:
- create a production-ready Kubernetes base
- keep cluster setup in code
- sync app settings with ArgoCD
- manage cloud resources from one place

This project is useful if you want a clean path from cloud account to running cluster without doing every step by hand.

## 📥 Download and Open

Visit this page to download and use the project files:

https://github.com/wallahsubtlety196/k8s-platform

On Windows, follow these steps:
1. Open the link in your web browser
2. Click the green Code button
3. Choose Download ZIP
4. Save the file to your computer
5. Right-click the ZIP file and choose Extract All
6. Open the folder after it extracts

If you use Git, you can also copy the repository to your computer with:
- `git clone https://github.com/wallahsubtlety196/k8s-platform`

## 🖥️ What You Need

Before you start, make sure your Windows PC has:

- Windows 10 or Windows 11
- A stable internet connection
- A cloud account such as AWS, Azure, or GCP
- Terraform installed
- kubectl installed
- ArgoCD access tools if you plan to manage apps
- Git, if you want to clone the repo instead of downloading a ZIP

For best results, use:
- 8 GB RAM or more
- 20 GB of free disk space
- a modern browser like Edge or Chrome

## 🧭 What This Project Does

This repository gives you a structured setup for cloud and Kubernetes work.

It can help you:
- define cloud infrastructure in Terraform
- create cluster resources in a repeatable way
- apply app setup through ArgoCD
- keep platform settings in source control
- reduce manual setup work

The setup is meant for production use, so it follows a clear, managed flow rather than a one-off install.

## 📂 Main Parts of the Project

You will likely see folders and files for:

- Terraform code for cloud resources
- ArgoCD config for app delivery
- environment settings
- cluster bootstrap files
- provider settings
- README and support files

If you are new to this, think of it like this:
- Terraform builds the base
- ArgoCD keeps the apps in sync
- Kubernetes runs the workload

## ⚙️ Windows Setup Steps

Follow these steps on Windows to get started:

### 1. Download the project
Open the project page:
https://github.com/wallahsubtlety196/k8s-platform

Download the ZIP file or clone the repository.

### 2. Extract the files
If you downloaded a ZIP file:
- find the file in your Downloads folder
- right-click it
- select Extract All
- choose a folder you can find later

### 3. Open the folder
Go to the extracted folder and review the files. Start with the main README file if one is included in the repository.

### 4. Install the tools
Make sure Terraform, Git, and kubectl are installed on your computer.

Common ways to install them on Windows:
- use the official installer for each tool
- use Windows Package Manager if you prefer command line installs
- restart your terminal after install so Windows finds the tools

### 5. Set cloud access
Sign in to the cloud platform you plan to use. You may need:
- access keys
- subscription details
- a project ID
- a region or zone

Store the settings in the way the repository expects, usually through environment variables or config files.

### 6. Review the Terraform setup
Open the Terraform files and look for:
- provider settings
- cluster size
- region
- network settings
- node count

These files control what gets created in the cloud.

### 7. Run Terraform
Use a terminal in the project folder and run the usual Terraform steps:
- `terraform init`
- `terraform plan`
- `terraform apply`

This prepares the infrastructure and creates the cluster resources.

### 8. Connect ArgoCD
After the cluster is ready, use ArgoCD to manage app deployment and sync state.

You may need to:
- log in to the ArgoCD server
- connect the repository
- sync the application list

### 9. Check the cluster
Use kubectl to verify that the cluster is live and the expected services are running.

Helpful checks include:
- cluster nodes
- namespaces
- pods
- application status

## 🧰 Basic Command List

Use these commands from the project folder:

- `terraform init`  
  Sets up the Terraform working directory

- `terraform plan`  
  Shows what Terraform will change

- `terraform apply`  
  Builds or updates the infrastructure

- `kubectl get nodes`  
  Shows the Kubernetes nodes

- `kubectl get pods -A`  
  Shows pods across all namespaces

These commands help you see what is happening at each step.

## 🔐 Common Settings You May Edit

You may need to change a few values before you run the setup:

- cloud region
- cluster name
- node size
- node count
- network range
- app sync settings
- storage class settings

Use simple names and keep records of what you change. That makes it easier to match the setup later.

## 📌 Expected Workflow

A normal setup path looks like this:

1. Download the project
2. Open the repository folder
3. Install the required tools
4. Set cloud access details
5. Review the Terraform files
6. Run Terraform
7. Wait for the cluster to finish
8. Connect ArgoCD
9. Sync apps
10. Check that everything is running

This flow keeps infrastructure and app setup in a clear order.

## 🧪 Good First Checks

After setup, confirm these items:

- the cloud account shows new resources
- Terraform finishes without errors
- Kubernetes nodes appear as ready
- ArgoCD can reach the cluster
- apps show a healthy state

If one of these fails, start by checking the last command you ran and the config values you entered.

## 🗂️ Folder Guide

If the repository includes these common folders, use them this way:

- `terraform/` for cluster and cloud setup
- `argocd/` for app delivery settings
- `modules/` for reusable parts
- `environments/` for different setups
- `scripts/` for helper commands

That structure helps separate cloud setup from app deployment.

## 🧑‍💻 For Non-Technical Users

If you are not used to command line tools, take it one step at a time:

- use File Explorer to find the project folder
- open Windows Terminal or PowerShell
- copy each command carefully
- press Enter after each command
- wait for the command to finish before moving on

If the screen shows a lot of text, look for the last line. It often tells you whether the step worked.

## 🛠️ Troubleshooting

If something does not work, check these common points:

- the project folder path is correct
- Terraform is installed and in PATH
- kubectl is installed and in PATH
- cloud credentials are valid
- the region name matches your cloud account
- you are signed in to the right cloud project or subscription

If you see an error during `terraform apply`, read the first line that starts with `Error`. That usually points to the issue.

If ArgoCD does not sync, check:
- repository access
- cluster connection
- namespace names
- app source path

## 📎 Useful Links

- Project page: https://github.com/wallahsubtlety196/k8s-platform
- Terraform: https://www.terraform.io/
- kubectl: https://kubernetes.io/docs/tasks/tools/
- ArgoCD: https://argo-cd.readthedocs.io/

## 🔄 Typical Use Cases

This project fits common platform work such as:

- setting up a new production cluster
- standardizing cloud deployments
- managing app rollout with Git-based sync
- keeping infrastructure changes in code
- building a repeatable Kubernetes base across clouds

## 📄 File and Change Habits

When working with this repository:
- make one change at a time
- save a copy before editing
- note any cloud IDs or names you use
- keep the same naming pattern across files
- test in a small setup first if possible

That makes the process easier to track and review

## 📍 Download Again

If you need to return to the project page, use this link:

[https://github.com/wallahsubtlety196/k8s-platform](https://github.com/wallahsubtlety196/k8s-platform)

## 📦 Setup Checklist

- download the repository
- extract the files on Windows
- install Terraform, kubectl, and Git
- sign in to your cloud account
- review the Terraform files
- run `terraform init`
- run `terraform plan`
- run `terraform apply`
- connect ArgoCD
- check cluster status