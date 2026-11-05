#!/usr/bin/env bash
# Static build information. Never source user-controlled configuration.
# Referenced by other modules sourced through bin/uir.
# shellcheck disable=SC2034
readonly UIR_VERSION='1.0.0-rc1'
# Referenced by doctor.sh after the entry point sources this file.
# shellcheck disable=SC2034
readonly UIR_PRODUCT='Ubuntu Incident Response Toolkit'
# Referenced by export.sh after the entry point sources this file.
# shellcheck disable=SC2034
readonly UIR_REDACTION_POLICY='1'
