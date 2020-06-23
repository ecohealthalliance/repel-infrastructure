#!/bin/bash

if [ "$IS_LOCAL" == "no" ]
then
  npm start;
else
  exit 0;
fi
