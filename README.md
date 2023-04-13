# Diztributed

Solving Fly.io Distributed Systems Challenges with Zig

## Payload examples

init

```
{ "src": "c1", "dest": "n1", "body": { "type": "init", "msg_id": 1, "node_id": "n1", "node_ids": ["n1", "n2", "n3"] } }
```

```
{"id":0,"src":"c0","dest":"n0","body":{"type":"init","node_id":"n0","node_ids":["n0"],"msg_id":1}}
```

echo

```
{ "src": "c1", "dest": "n1", "body": { "type": "echo", "msg_id": 1, "echo": "Please echo 35" } }
```
