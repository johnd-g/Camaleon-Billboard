import 'package:camaleon_billboard/domain/entities/menu_section.dart';
import 'package:camaleon_billboard/domain/repositories/billboard_repository.dart';

class LoadBillboardUseCase {
  LoadBillboardUseCase(this._repository);

  final BillboardRepository _repository;

  Future<BillboardBoard> call({
    required String compName,
    required bool sortAlphabetical,
  }) {
    return _repository.loadBoard(
      compName: compName,
      sortAlphabetical: sortAlphabetical,
    );
  }
}
