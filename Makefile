export AWS_PROFILE        ?= sunrise201911-team-d
export AWS_DEFAULT_REGION := ap-northeast-1

.PHONY: all install imports fmt test run build clean upload

GOOS   ?=
GOARCH ?=
GOSRC  := $(GOPATH)/src
COUNT := 1

all: install run

install:

imports:
	goimports -w .

fmt:
	gofmt -w .

test:
	go test -v -tags=unit $$(go list ./... | grep -v '/vendor/')

test/curl:
	curl -v localhost:8081/hakaru?name=denden&value=10

run: main.go
	go run main.go

build: test
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build -o hakaru

clean:
	rm -rf hakaru *.tgz

# lcoal mysqld on docker

mysql_run:
	docker run --rm -d \
	  --name sunrise2019-hakaru-db \
	  -e MYSQL_ROOT_PASSWORD=password \
	  -e MYSQL_DATABASE=hakaru \
	  -e TZ=Asia/Tokyo \
	  -p 13306:3306 \
	  -v $(CURDIR)/db/data:/var/lib/mysql \
	  -v $(CURDIR)/db/my.cnf:/etc/mysql/conf.d/my.cnf:ro \
	  -v $(CURDIR)/db/init:/docker-entrypoint-initdb.d:ro \
	  mysql:5.6 \
	  mysqld --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci

mysql_connect:
	mysql -P 13306 -u root -h 127.0.0.1 -p
# deployment

artifacts.tgz: provisioning/instance
	$(MAKE) build GOOS=linux GOARCH=amd64
	tar czf artifacts.tgz hakaru db provisioning/instance

ARTIFACTS_BUCKET := $(AWS_PROFILE)-hakaru-artifacts

# ci からアップロードできなくなった場合のターゲット
upload: clean artifacts.tgz
	aws s3 cp artifacts.tgz s3://$(ARTIFACTS_BUCKET)/latest/artifacts.tgz
	aws s3 cp artifacts.tgz s3://$(ARTIFACTS_BUCKET)/$$(git rev-parse HEAD)/artifacts.tgz

new_instance:
	aws ec2 run-instances \
		--count $(COUNT) \
		--user-data file://user_data.sh \
		--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=hakaru-from-cli}]' \
		--image-id ami-038456c23bd2a69e9 \
		--security-group-ids sg-0e7591374f4460444  \
		--instance-type c5.large \
		--subnet-id subnet-020c52b7776a2c1f3 \
		--iam-instance-profile Name="hakaru"


tes:
	cd _files \
	aws ec2 describe-instances \
	--profile sunrise201911-team-d \
	--region ap-northeast-1 \
	--filters Name=instance-state-name,Values=running |\
	jq '.Reservations[].Instances[] |\
	select( .Tags[].Key == "Name" and (.Tags[].Value | test("^hakaru"))) |\
	.InstanceId' |\
	uniq |\
	sed '/s\"/d' |\
	AWS_PROFILE=sunrise201911-team-d xargs -IIP_ADDR ssh -i id_rsa ec2-user@IP_ADDR "ulimit -n 4096"
