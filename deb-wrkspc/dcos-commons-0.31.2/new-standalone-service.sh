#!/bin/bash

set -e

CLEANUP_PATH=`pwd`
VERSION="0.31.2"

cleanup() {
    debug "Cleaning up"
    rm -rf $CLEANUP_PATH/template.zip
}

trap cleanup INT TERM

error_msg() {
    echo "---"
    echo "Failed to generate the project: Exited early at $0:L$1"
    echo "To try again, re-run this script."
    echo "---"
}
trap 'error_msg ${LINENO}' ERR

info() {
    echo $1
}

debug() {
    if [[ -z "${DEBUG// }" ]]; then
        return
    fi
    echo "DEBUG: $1"
}

PROJECT_NAME=$1
PROJECT_PATH=$2

if [[ -z "${PROJECT_NAME// }" ]]; then
    echo "You must provide the name of the project as the first argument"
    echo "Usage: ./new-standalone-service.sh project-name"
    echo "Example: ./new-standalone-service.sh kafka"
    cleanup
    exit 1
fi

if [[ -z "${PROJECT_PATH// }" ]]; then
    PROJECT_PATH=$(pwd)
fi

debug "Scaffolding $PROJECT_NAME from template"

cp -R frameworks/template $PROJECT_PATH/$PROJECT_NAME
cp -R tools $PROJECT_PATH/$PROJECT_NAME/tools
cp -R testing $PROJECT_PATH/$PROJECT_NAME/testing
cp ./.gitignore $PROJECT_PATH/$PROJECT_NAME
rm -rf $PROJECT_PATH/$PROJECT_NAME/build
rm -rf $PROJECT_PATH/$PROJECT_NAME/cli/dcos-*/*template*
rm -rf $PROJECT_PATH/$PROJECT_NAME/cli/dcos-*/.*template*
rm -rf $PROJECT_PATH/$PROJECT_NAME/build.sh

cat > $PROJECT_PATH/$PROJECT_NAME/build.sh <<'EOF'
#!/bin/bash
set -e
SERVICE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR=$SERVICE_DIR/build/distributions
SERVICE_NAME=template
BOOTSTRAP_DIR=disable \
EXECUTOR_DIR=disable \
TEMPLATE_DOCUMENTATION_PATH="http://YOURNAMEHERE.COM/DOCS" \
TEMPLATE_ISSUES_PATH="http://YOURNAMEHERE.COM/SUPPORT" \
    $SERVICE_DIR/tools/build_framework.sh \
        $SERVICE_NAME \
        $SERVICE_DIR \
        --artifact "$BUILD_DIR/${SERVICE_NAME}-scheduler.zip" \
        $@
EOF
chmod +x $PROJECT_PATH/$PROJECT_NAME/build.sh

cat > $PROJECT_PATH/$PROJECT_NAME/settings.gradle << EOF
rootProject.name = '$PROJECT_NAME'
EOF

cat > $PROJECT_PATH/$PROJECT_NAME/tests/__init__.py << EOF
import sys
import os.path
# Add /testing/ to PYTHONPATH:
this_file_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.normpath(os.path.join(this_file_dir, '..', 'testing')))
EOF

mv $PROJECT_PATH/$PROJECT_NAME/cli/dcos-template $PROJECT_PATH/$PROJECT_NAME/cli/dcos-$PROJECT_NAME
mv $PROJECT_PATH/$PROJECT_NAME/src/main/java/com/mesosphere/sdk/template/ $PROJECT_PATH/$PROJECT_NAME/src/main/java/com/mesosphere/sdk/$PROJECT_NAME/
mv $PROJECT_PATH/$PROJECT_NAME/src/test/java/com/mesosphere/sdk/template/ $PROJECT_PATH/$PROJECT_NAME/src/test/java/com/mesosphere/sdk/$PROJECT_NAME/

UPPER_CASE_PROJECT_NAME=$(echo $PROJECT_NAME | awk '{print toupper($0)}')

find $PROJECT_PATH/$PROJECT_NAME -type f -exec sed -i.bak "s/template/$PROJECT_NAME/g; s/TEMPLATE/$UPPER_CASE_PROJECT_NAME/g; s/template/$PROJECT_NAME/g" {} \;
find $PROJECT_PATH/$PROJECT_NAME -type f -name *.bak -exec rm -f {} \;

sed -i.bak "s/compile project(\":scheduler\")/compile \"mesosphere:scheduler:$VERSION\"/g" $PROJECT_PATH/$PROJECT_NAME/build.gradle
sed -i.bak "s/compile project(\":executor\")/compile \"mesosphere:executor:$VERSION\"/g" $PROJECT_PATH/$PROJECT_NAME/build.gradle
sed -i.bak "s/testCompile project(\":testing\")/testCompile \"mesosphere:testing:$VERSION\"/g" $PROJECT_PATH/$PROJECT_NAME/build.gradle
sed -i.bak '/distZip.dependsOn ":executor:distZip"/d' $PROJECT_PATH/$PROJECT_NAME/build.gradle
sed -i.bak '/distZip.finalizedBy copyExecutor/d' $PROJECT_PATH/$PROJECT_NAME/build.gradle
sed -i.bak '/mavenCentral()/i jcenter()' $PROJECT_PATH/$PROJECT_NAME/build.gradle
rm -f $PROJECT_PATH/$PROJECT_NAME/build.gradle.bak

GRADLEW=$(pwd)/gradlew

pushd $PROJECT_PATH/$PROJECT_NAME
$GRADLEW wrapper --gradle-version 3.4.1
popd

# copy test.sh and test-runnser.sh, adjust test-runner.sh
cp test.sh test-runner.sh $PROJECT_PATH/$PROJECT_NAME
sed -i "s/FRAMEWORK_DIR=\$REPO_ROOT_DIR\/frameworks\/\${framework}/FRAMEWORK_DIR=\$REPO_ROOT_DIR/g" $PROJECT_PATH/$PROJECT_NAME/test-runner.sh

# copy govendor and dcos-commons cli, adjust symbolic links
rsync -avz --delete govendor $PROJECT_PATH/$PROJECT_NAME
rm $PROJECT_PATH/$PROJECT_NAME/cli/dcos-$PROJECT_NAME/vendor
ln -s ../../govendor $PROJECT_PATH/$PROJECT_NAME/cli/dcos-$PROJECT_NAME/vendor
rm $PROJECT_PATH/$PROJECT_NAME/govendor/github.com/mesosphere/dcos-commons/cli
rsync -avz --delete cli $PROJECT_PATH/$PROJECT_NAME/govendor/github.com/mesosphere/dcos-commons/

# reference bootstrap and executor release artifacts from resource.json
sed -i "s/{{artifact-dir}}\/bootstrap.zip/http:\/\/downloads.mesosphere.com\/dcos-commons\/artifacts\/$VERSION\/bootstrap.zip/g" $PROJECT_PATH/$PROJECT_NAME/universe/resource.json
sed -i "s/{{artifact-dir}}\/executor.zip/http:\/\/downloads.mesosphere.com\/dcos-commons\/artifacts\/$VERSION\/executor.zip/g" $PROJECT_PATH/$PROJECT_NAME/universe/resource.json

# fix bootstrap option in cmd of marathon.json.mustache
sed -i "s/-$PROJECT_NAME=false/-template=false/g" $PROJECT_PATH/$PROJECT_NAME/universe/marathon.json.mustache


echo "New project created successfully"
