all: up

UID=$(shell id -u)
export UID

www-root:
	mkdir -p www-root

up: www-root
	docker-compose up --build --remove-orphans -d

down:
	docker-compose down

clean:
	rm -r www-root
