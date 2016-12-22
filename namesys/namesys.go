package namesys

import (
	"context"
	"strings"
	"time"

	"github.com/ipfs/go-ipfs/path"

	ds "gx/ipfs/QmRWDav6mzWseLWeYfVd5fvUKiVe9xNH29YfMF438fG364/go-datastore"
	routing "gx/ipfs/QmbkGVaN9W6RYJK4Ws5FvMKXKDqdRQ5snhtaa92qP6L8eU/go-libp2p-routing"
	peer "gx/ipfs/QmfMmLGoKzCHDN7cGgk64PJr4iipzidDRME8HABSJqvmhC/go-libp2p-peer"
	ci "gx/ipfs/QmfWDLQjGjVe4fr5CoztYW2DYYjRysMJrFe1RCsXLPTf46/go-libp2p-crypto"
)

// mpns (a multi-protocol NameSystem) implements generic IPFS naming.
//
// Uses several Resolvers:
// (a) IPFS routing naming: SFS-like PKI names.
// (b) dns domains: resolves using links in DNS TXT records
// (c) proquints: interprets string as the raw byte data.
//
// It can only publish to: (a) IPFS routing naming.
//
type mpns struct {
	ipnsPub    *ipnsPublisher
	dhtRes     *routingResolver
	resolvers  map[string]resolver
	publishers map[string]RePublisher
}

// NewNameSystem will construct the IPFS naming system based on Routing
func NewNameSystem(r routing.ValueStore, ds ds.Datastore, cachesize int) NameSystem {
	ipnsPub := NewRoutingPublisher(r, ds)
	dhtRes := NewRoutingResolver(r, cachesize)
	return &mpns{
		ipnsPub: ipnsPub,
		dhtRes: dhtRes,
		resolvers: map[string]resolver{
			"dns":      newDNSResolver(),
			"proquint": new(ProquintResolver),
			"dht":      dhtRes,
		},
		publishers: map[string]RePublisher{
			"/ipns/": ipnsPub,
		},
	}
}

const DefaultResolverCacheTTL = time.Minute

// Resolve implements Resolver.
func (ns *mpns) Resolve(ctx context.Context, name string) (path.Path, error) {
	return ns.ResolveN(ctx, name, DefaultDepthLimit)
}

// ResolveN implements Resolver.
func (ns *mpns) ResolveN(ctx context.Context, name string, depth int) (path.Path, error) {
	if strings.HasPrefix(name, "/ipfs/") {
		return path.ParsePath(name)
	}

	if !strings.HasPrefix(name, "/") {
		return path.ParsePath("/ipfs/" + name)
	}

	return resolve(ctx, ns, name, depth, "/ipns/")
}

// resolveOnce implements resolver.
func (ns *mpns) resolveOnce(ctx context.Context, name string) (path.Path, error) {
	if !strings.HasPrefix(name, "/ipns/") {
		name = "/ipns/" + name
	}
	segments := strings.SplitN(name, "/", 4)
	if len(segments) < 3 || segments[0] != "" {
		log.Warningf("Invalid name syntax for %s", name)
		return "", ErrResolveFailed
	}

	for protocol, resolver := range ns.resolvers {
		log.Debugf("Attempting to resolve %s with %s", segments[2], protocol)
		p, err := resolver.resolveOnce(ctx, segments[2])
		if err == nil {
			if len(segments) > 3 {
				return path.FromSegments("", strings.TrimRight(p.String(), "/"), segments[3])
			} else {
				return p, err
			}
		}
	}
	log.Warningf("No resolver found for %s", name)
	return "", ErrResolveFailed
}

// Publish implements Publisher
func (ns *mpns) Publish(ctx context.Context, name ci.PrivKey, value path.Path) error {
	err := ns.ipnsPub.Publish(ctx, name, value)
	if err != nil {
		return err
	}
	ns.addToDHTCache(name, value, time.Now().Add(DefaultRecordTTL))
	return nil
}

func (ns *mpns) PublishWithEOL(ctx context.Context, name ci.PrivKey, value path.Path, eol time.Time) error {
	err := ns.ipnsPub.PublishWithEOL(ctx, name, value, eol)
	if err != nil {
		return err
	}
	ns.addToDHTCache(name, value, eol)
	return nil
}

func (ns *mpns) RePublish(ctx context.Context, name ci.PrivKey, eol time.Time) error {
	return ns.ipnsPub.RePublish(ctx, name, eol)
}

func (ns *mpns) Upload(ctx context.Context, pk ci.PubKey, record []byte) (peer.ID, uint64, uint64, path.Path, error) {
	return ns.ipnsPub.Upload(ctx, pk, record)
}

func (ns *mpns) addToDHTCache(key ci.PrivKey, value path.Path, eol time.Time) {
	rr := ns.dhtRes
	if rr.cache == nil {
		// resolver has no caching
		return
	}

	var err error
	value, err = path.ParsePath(value.String())
	if err != nil {
		log.Error("could not parse path")
		return
	}

	name, err := peer.IDFromPrivateKey(key)
	if err != nil {
		log.Error("while adding to cache, could not get peerid from private key")
		return
	}

	if time.Now().Add(DefaultResolverCacheTTL).Before(eol) {
		eol = time.Now().Add(DefaultResolverCacheTTL)
	}
	rr.cache.Add(name.Pretty(), cacheEntry{
		val: value,
		eol: eol,
	})
}
