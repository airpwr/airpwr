ARG BASE_REF
FROM $BASE_REF
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue';"]
ARG REF
RUN iex (iwr -UseBasicParsing "https://raw.githubusercontent.com/airpwr/airpwr/${env:REF}/src/install.ps1")
CMD ["pwr", "version"]