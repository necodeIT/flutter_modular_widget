import 'package:mcquenji_core/mcquenji_core.dart';

/// Generic test repository that exposes helpers to drive [AsyncValue] state.
class TestRepository<T> extends Repository<AsyncValue<T>> {
  TestRepository() : super(AsyncValue.loading());

  void setData(T value) => emit(AsyncValue.data(value));

  void setError(Object error) => emit(AsyncValue.error(error));
}
