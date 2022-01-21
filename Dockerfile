# escape=`
ARG BASE_REF
FROM $BASE_REF
ADD .\src\pwr.ps1 \pwr\cmd\pwr.ps1
RUN setx /M Path "\pwr\cmd;%Path%" && setx /M PwrHome "\pwr"
CMD ["pwsh"]