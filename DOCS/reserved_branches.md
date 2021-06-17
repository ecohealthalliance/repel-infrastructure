# Reserved Branches

We have long-running branches that are used to deploy code to various servers:

* production
* development

A typical workflow would be to work on your personal branch and when it's ready for remote testing or staging it should be pulled into the development branch.  When the remote development branch is updated a GitHub Action will deploy that code to our development server.  When the code is ready for production the code should be pulled into the production branch.  When the remote production branch is updated a GitHub Action will deploy the code to our production server.
