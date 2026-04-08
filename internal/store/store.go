package store

import "context"

type Store struct{}

func Open(_ context.Context, _ string) (*Store, error) {
	return &Store{}, nil
}

func (s *Store) Close() error {
	return nil
}
