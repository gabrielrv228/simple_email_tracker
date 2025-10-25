review the manual setup md
add the variables to the github repo as secrets
test the pipeline
test how other people can quickly fork/clone and deploy, and create instructions for it.
Better to leave to the users the task of creating the role that will gha use


Only remains apart from the previous to add the terraform.tfvars to the repo variables, and to document how is a great bulletproof ultra-automated solution that is created and managed with minimal permissions. Remember to add support for cloudwatch logging.

create a good readme.


Just remains to create a guide that explains how to set everything up from scratch. The ideal thing is a youtube video.

- Fork the repo

- Clone it

- generate aws credentials

- log in

- run the setup script

- get a bot token and a chat id, add the bot to the channel

- add the gha env variables

- run it


Add a small code that sends the function url to telegram once deployed.