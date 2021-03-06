#!/usr/bin/env bash

set -o nounset
set -o errtrace
set -o errexit

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__CONFIG="./.config.sh"

[[ -f ${__CONFIG} ]] && source ${__CONFIG}


setup_source(){
  # args:
  local function_name="${1:?arr-err: lambdas name, e.g. UsersManager}"
  # user role: e.g. arn:aws:iam::225958099118:role/CatalogerRole
  local function_role="${2:?arr-err: AWS IAM Role}"
  local function_region="${3:-us-east-1}"
  local function_runtime="${4:-python3.6}"
  local function_table="${5:-}"

  # config: root
  local root_path="$(pwd)/${function_name}"
  # root branches
  local code_path="${root_path}/Code"
  local libs_path="${root_path}/Libs"
  local package_path="${root_path}/Package"
  local tests_path="${root_path}/Tests"
  local conf_path="${root_path}/.config.sh"
  local env_vars="DB_REGION=${function_region}"

  if [[ -n "${function_table}" ]]; then
    env_vars+=", DB_TABLE=${dynamo_table}"
  fi

  mkdir -p ${code_path} &>/dev/null
  mkdir -p ${libs_path} &>/dev/null
  mkdir -p ${package_path} &>/dev/null
  mkdir -p ${tests_path} &>/dev/null

  #
  # Clone Lambda's Template Repository
  #
  git clone git@github.com:noize-e/lambda-microservice.git ${code_path} ;
  # clean template's repo trace
  rm -rf ${code_path}/.git &>/dev/null

  if [[ ! -d ${conf_path} ]] ; then
    printf "\
_LAMBDA_NAME='${function_name}'
_LAMBDA_HANDLER='lambda_function.lambda_handler'
_LAMBDA_REGION='${function_region}'
_LAMBDA_RUNTIME='${function_runtime}'
_ROLA_ARN='${function_role}'
_CODE_PATH='${code_path}'
_LIBS_PATH='${libs_path}'
_ENVVARS='${env_vars}'
_PACKAGE='${package_path}/${function_name}.zip'
_TESTS_PATH='${tests_path}'
" > ${conf_path}
  fi
}


build_package(){
  if [[ -f ${_PACKAGE} ]]; then
    rm -vf ${_PACKAGE};
  fi

  pushd "${_LIBS_PATH}" && \
    zip -r9 "${_PACKAGE}" . && \
      popd 2>/dev/null

  pushd '${_CODE_PATH}' && \
    zip "${_PACKAGE}" -rg "./lambda_function.py" "./helpers/" "./dynamo/" && \
      popd ;

  echo -e "Package created.\n$(ls -l ${_PACKAGE})"
}


deploy_lambda(){
  aws lambda create-function --function-name ${_LAMBDA_NAME} \
                                  --zip-file fileb://${_PACKAGE} \
                                   --handler ${_LAMBDA_HANDLER} \
                               --environment Variables={${_ENVVARS}} \
                                   --runtime ${_LAMBDA_RUNTIME} \
                                      --role ${_ROLA_ARN}
}


update_lambda(){
  case "${1:?arg-err: action <code>}" in
    # config )
        # aws lambda \
        #   update-function-configuration --function-name ${_LAMBDA_NAME} \
        #                                 --environment Variables=${env_vars}
    #  ;;
    code )
        case "${2:-packge}" in
          packge )
              build_package
            ;;
        esac

        aws lambda \
          update-function-code --function-name ${_LAMBDA_NAME} \
                               --zip-file fileb://${_PACKAGE}
      ;;
  esac
}

#
# Excute a pre-defined test
#
exec_test(){
  test_file="${_TESTS_PATH}/${_LAMBDA_NAME}.txt"

  echo "Running test... " && \
  aws lambda invoke --function-name ${_LAMBDA_NAME} --payload file://${test_file}
}


print_help(){
  printf "\
Help: lamda <-cmd [options]>

  -new:   Create and setup a lambda's source code
          Args:   <1:name>     AWS Lambda's Name, e.g. 'UsersManager'
                  <2:role>     AWS IAM Role, e.g. arn:aws:iam::225958099118:role/CatalogerRole
                  <3:region>   AWS Region     [Optional] default: us-east-1
                  <4:runtime>  Lambda Runtime [Optional] default: python3.6
                  <5:table>    DynamoDB Table [Optional]

  -deploy Create the lambda function in AWS console

  -update Updates lambda's configuration & code in AWS console
          Args:   <code [skip-pkg]>

  -test:  Store in a text file with the given lambda's name the follwing data structure
          JSON Schema:
            {
                \"path\": \"/lambda/fn/path\",
                \"httpMethod\": \"GET\",
                \"headers\": {
                    \"Accept\": \"*/*\",
                    \"content-type\": \"application/json; charset=UTF-8\"
                },
                \"queryStringParameters\": {},
                \"pathParameters\": {},
                \"requestContext\": {},
                \"body\": \"{}\"
            }
"
}

case "${1:?arg-err: action <-new|-deploy|-update|-test>}" in
  -new)
      setup_source ${2:-} ${3:-} ${4:-} ${5:-}
    ;;
  -deploy)
      build_package && deploy_lambda
    ;;
  -update)
      update_code ${2:-} ${3:-}
    ;;
  -test)
      exec_test
    ;;
  -help)
      print_help
    ;;
esac
