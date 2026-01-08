#!/bin/bash
cd /home/site/wwwroot
dotnet ef database update --no-build
