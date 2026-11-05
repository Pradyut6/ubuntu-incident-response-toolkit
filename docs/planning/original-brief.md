# Ubuntu Server Incident Response & Automated Troubleshooting Toolkit

> **Document type:** Original project brief  
> **Status:** Unpolished proposal, faithfully formatted in Markdown  
> **Note:** The original wording and scope have been preserved; only Markdown structure has been added.

## Goal

Hi, I would like to create a detailed plan for a Vibe-coded project that I'm about to build. Before we build it out, I would like you to create the detailed plan from the initial crafted unpolished plan I will provide, allow me to review it, and ask me any clarifying questions that you need in order for us to build this and for it to be crystal clear with no ambiguity in small secure increments step by step testing every functionality on the way.

This project will be an impactful gem in my resume which will follow the STAR framework. It will be a career deciding factor when shown to a recruiter. We are building this to address real life problems like investigating outages, server failures, automate diagnostic collection etc. Don't make it look vibe-coded as it may reduce my chances of getting a job. All of this we are doing is to create a near perfect portfolio project for a job opening in Canonical. Also help me in implementing them end to end with guidance just like performing a guided tutorial with milestone checks. We will build this command line application in Bash then develop a graphical dashboard later. At the end we will craft a beautiful state of the art README for this project that will also include the steps to use the toolkit on their own machine. Now while we create this project we will build and test this project locally step by step hand-holding me through all the steps and tasks and if we encounter any bug we will fix it and continue from where we left off. Lastly we will publish this project in my resume. Lastly one more thing, our toolkit should have the feature to allow user to retain, download logs - the use should have the feature to decide on logs retention and the logs should be saved in the best format when it comes to saving log files that donot take up much space. Once we complete all of this we will create a repo in github, push all aur work there and and add our README.

## Project proposal

### Project name

**Ubuntu Server Incident Response & Automated Troubleshooting Toolkit**

**Domain:** Linux System Administration & IT Technical Support

**Objective:** Build an Ubuntu troubleshooting environment where you deliberately create realistic server failures, investigate them using logs and system commands, resolve them, and automate diagnostic collection.

### What to implement

| Component | Practical implementation |
| --- | --- |
| Ubuntu environment | Install Ubuntu Server 24.04 LTS in VirtualBox or another VM environment |
| Service troubleshooting | Diagnose and repair failed Nginx, SSH and systemd services |
| System administration | Investigate permission errors, package failures, high CPU usage and disk exhaustion |
| Log analysis | Work with `journalctl`, `dmesg`, `/var/log`, and `systemctl` |
| Bash automation | Write a script that gathers service status, system health and relevant logs |
| Incident documentation | Maintain 10–12 documented troubleshooting cases |
| Knowledge base | Write step-by-step troubleshooting articles based on the incidents |

### Example troubleshooting scenario

**INC-007 — Nginx service unavailable**

**Severity:** High

Simulated employee reports that an internal web application cannot be accessed.

#### Investigation

```bash
systemctl status nginx
journalctl -u nginx -n 50
sudo nginx -t
sudo ss -tulpn
```

Identify the configuration or port-binding failure, correct it, restart the service, and verify application accessibility. Rather than simply displaying diagnostic information on the terminal, our application should automatically collect, organize, securely store, and export diagnostic logs for future investigation. Search stored incidents by date, service name, incident ID or error message. Compare system diagnostics before troubleshooting and after the issue is resolved. Package logs, metadata and reports into a compressed `.tar.gz` archive for technical handoff. Save diagnostic snapshots when requested. Optionally trigger collection when a monitored service fails. For Secure storage and retention - Restrict file permissions, redact sensitive data before sharing, establish retention periods, and prevent unrestricted log accumulation.

### Evidence to publish

Sanitized logs, root-cause analysis, before-and-after evidence, incident timeline, and a troubleshooting knowledge-base article.
