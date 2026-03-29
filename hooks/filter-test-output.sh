#!/usr/bin/env bash

grep -E "FAIL|ERROR|Error:|failed|PASS|Tests:|Test Suites:" || true
