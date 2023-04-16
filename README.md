# Diztributed

Solving Fly.io Distributed Systems Challenges with Zig

## Payload Tests

#### init

Example Message

```
{"id":0,"src":"c0","dest":"n0","body":{"type":"init","node_id":"n0","node_ids":["n0"],"msg_id":0}}
```

#### echo

Command

```
./maelstrom test -w echo --bin ~/go/bin/maelstrom-echo --node-count 1 --time-limit 10
```

Example Message

```
{"id":1,"src":"c1","dest":"n1","body":{"type":"echo","msg_id": 1,"echo":"Please echo 35"}}
```

#### generate

Command

```
./maelstrom test -w unique-ids --bin ~/github.com/charlieroth/diztributed/zig-out/bin/diztributed --time-limit 30 --rate 1000 --node-count 3 --availability total --nemesis partition
```

Example Message

```
{"id": 1, "src": "c1", "dest": "n1", "body": {"type": "generate", "msg_id": 1}}
```