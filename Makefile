.PHONY: cleanup provision-dev-cluster install-metallb configure-tuntap argocd-bootstrap set-argocd-password

CURRENT_DIR=$(shell pwd)
PASSWORD=KubernetesIsCool
BCRYPT_PASSWORD=`htpasswd -bnBC 10 "" ${PASSWORD} | tr -d ':\n'`
PASSWORD64=$(shell echo ${BCRYPT_PASSWORD})

list:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

cleanup:
	- ./k3d-resources/docker-tuntap-osx/sbin/docker_tap_uninstall.sh
	echo "Wait till docker is restarted."
	sleep 60
	echo "..done"
	k3d cluster delete dev-ld

provision-dev-cluster:
	k3d cluster create dev-ld --api-port 6443 -p 8080:80@loadbalancer --agents 2 \
		--k3s-server-arg '--flannel-backend=none' --k3s-server-arg '--no-deploy=traefik' \
		--volume "$(CURRENT_DIR)/k3d-resources/calico.yaml:/var/lib/rancher/k3s/server/manifests/calico.yaml"

install-metallb:
	# https://kubernetes.github.io/ingress-nginx/deploy/baremetal/
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/metallb.yaml
	# On first install only
	kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
	kubectl apply -f $(CURRENT_DIR)/k3d-resources/metal-lb-layer2-config.yaml

configure-tuntap:
	# https://blog.kubernauts.io/k3s-with-k3d-and-metallb-on-mac-923a3255c36e
	# only needed for Mac
	# create a bridge interface between the Physical Machine and the Host Virtual Machine.
	k3d cluster stop dev-ld
	./k3d-resources/docker-tuntap-osx/sbin/docker_tap_install.sh
	echo "Wait till docker is restarted."
	sleep 60
	echo "..done"
	./k3d-resources/docker-tuntap-osx/sbin/docker_tap_up.sh
	sudo route -v add -net 172.18.0.0 -netmask 255.255.255.0 10.0.75.2
	k3d cluster start dev-ld
argocd-bootstrap:
	kustomize build ./argocd-bootstrap/argocd-nginx-bootstrap | kubectl apply -f -

set-argocd-password:
	# update admin password
	kubectl -n argocd patch secret argocd-secret -p '{"stringData": {"admin.password": "${PASSWORD64}", "admin.passwordMtime": "'$(shell date +%FT%T%Z)'"}}'
	kubectl -n argocd get ingress
