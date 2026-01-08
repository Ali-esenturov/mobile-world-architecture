#!/bin/bash

set -e

echo "Waiting for containers to be ready..."
sleep 8

echo "Initializing CONFIG SERVER replica set..."
docker compose exec -T configSrv mongosh --port 27017 --eval '
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
'

sleep 3

echo "Initializing SHARD 1 replica set..."
docker compose exec -T shard1a mongosh "mongodb://shard1a:27018" --eval '
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1a:27018" },
    { _id: 1, host: "shard1b:27018" },
    { _id: 2, host: "shard1c:27018" }
  ]
})
'

sleep 3

echo "Initializing SHARD 2 replica set..."
docker compose exec -T shard2a mongosh "mongodb://shard2a:27019" --eval '
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2a:27019" },
    { _id: 1, host: "shard2b:27019" },
    { _id: 2, host: "shard2c:27019" }
  ]
})
'

sleep 4

echo "Initializing MONGOS router and adding shards..."
docker compose exec -T mongos_router mongosh --port 27020 --eval '
sh.addShard("shard1/shard1a:27018,shard1b:27018,shard1c:27018");
sh.addShard("shard2/shard2a:27019,shard2b:27019,shard2c:27019");
'

echo "Enabling sharding for database 'somedb'..."
docker compose exec -T mongos_router mongosh --port 27020 --eval '
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
'

echo "Inserting sample documents..."
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
use somedb
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
EOF

echo "Sharded cluster initialized successfully!"
