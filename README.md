# Pull Reporters

## Overview

Script to output details about all pull requests into a specified branch into a report in Excel (xlsx) file format.

## Installation
Set your GitHub credentials in config/octokit.yml (an example is provided).  To generate an oauth key for Octokit

    curl -u [user] -X POST -H "Content-Type: application/json" -d '{"scopes": ["repo"], "note" : "Admin script"}' https://api.github.com/authorizations

To pick the correct scope, follow the guidance on [This page](http://developer.github.com/v3/oauth/#scopes)    

## Usage
The script is invoked as:

    ruby script/main.rb -r repository -b branch_name

## Dependencies
See the Gemfile
