//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/utils/ELF/utils.hpp"
#include <vpux_elf/accessor.hpp>
#include <vpux_elf/reader.hpp>
#include "vpux/compiler/act_kernels/shave_binary_resources.h"
#include "vpux/compiler/dialect/VPURT/IR/ops.hpp"

namespace {

SmallString getSwKernelArchString(VPU::ArchKind archKind) {
    switch (archKind) {
    case VPU::ArchKind::NPU37XX:
        return SmallString("3720xx");
    case VPU::ArchKind::NPU40XX:
        return SmallString("4000xx");
    default:
        VPUX_THROW("unsupported archKind {0}", archKind);
        return SmallString("");
    }
}

}  // namespace

ArrayRef<uint8_t> vpux::ELF::getDataAndSizeOfElfSection(ArrayRef<uint8_t> elfBlob,
                                                        ArrayRef<StringRef> possibleSecNames) {
    auto accessor = elf::ElfDDRAccessManager(elfBlob.data(), elfBlob.size());
    auto elfReader = elf::Reader<elf::ELF_Bitness::Elf32>(&accessor);

    const uint8_t* secData = nullptr;
    uint32_t secSize = 0;

    bool secFound = false;

    for (size_t i = 0; i < elfReader.getSectionsNum(); ++i) {
        auto section = elfReader.getSection(i);
        const auto secName = section.getName();
        const auto sectionHeader = section.getHeader();

        for (auto& possibleSecName : possibleSecNames) {
            if (strcmp(secName, possibleSecName.data()) == 0) {
                secSize = sectionHeader->sh_size;
                secData = section.getData<uint8_t>();
                secFound = true;
                break;
            }
        }
    }
    VPUX_THROW_UNLESS(secFound, "Section {0} not found in ELF", possibleSecNames);

    return {secData, secSize};
}

size_t vpux::ELF::math::gcd(size_t a, size_t b) {
    if (b == 0) {
        return a;
    }
    return gcd(b, a % b);
}

size_t vpux::ELF::math::lcm(size_t a, size_t b) {
    return (a / vpux::ELF::math::gcd(a, b)) * b;
}

size_t vpux::ELF::getOffsetOfSymRef(ELF::SymbolReferenceMap& symRefMap, mlir::SymbolRefAttr symRef) {
    auto referencedOp = symRefMap.lookupSymbol(symRef);
    auto wrappableOp = mlir::dyn_cast<ELF::WrappableOpInterface>(referencedOp);

    VPUX_THROW_UNLESS(wrappableOp, "The relocInfo can't be retrieved for a non-binaryOpIf type reference");

    return wrappableOp.getMemoryOffset();
}

vpux::ELF::MainOp vpux::ELF::getElfMainOp(mlir::func::FuncOp funcOp) {
    auto mainOps = to_small_vector(funcOp.getOps<ELF::MainOp>());
    VPUX_THROW_UNLESS(mainOps.size() == 1, "Expected exactly one ELF mainOp. Got {0}", mainOps.size());
    return mainOps[0];
}

ArrayRef<uint8_t> vpux::ELF::getKernelELF(mlir::Operation* operation, StringRef kernelPath,
                                          ArrayRef<StringRef> sectionNames) {
    const auto& kernelInfo = ShaveBinaryResources::getInstance();
    const auto archKind = VPU::getArch(operation);
    const auto arch = getSwKernelArchString(archKind);
    const auto revisionID = VPU::getRevisionID(operation);
    llvm::ArrayRef<uint8_t> elfBlob;
    if (archKind == VPU::ArchKind::NPU40XX && revisionID.has_value() &&
        revisionID.value() >= VPU::RevisionID::REVISION_B) {
        llvm::StringRef suffix = "B0";
        elfBlob = kernelInfo.getElf(kernelPath, arch, suffix);
    } else {
        elfBlob = kernelInfo.getElf(kernelPath, arch);
    }
    return sectionNames.empty() ? elfBlob : vpux::ELF::getDataAndSizeOfElfSection(elfBlob, sectionNames);
}

mlir::SymbolRefAttr vpux::ELF::composeSectionObjectSymRef(ELF::ElfSectionInterface sectionIface, mlir::Operation* op) {
    auto sectionSymIface = mlir::cast<mlir::SymbolOpInterface>(sectionIface.getOperation());
    auto opSymIface = mlir::cast<mlir::SymbolOpInterface>(op);

    auto opRef = mlir::FlatSymbolRefAttr::get(opSymIface.getNameAttr());
    return mlir::SymbolRefAttr::get(sectionSymIface.getNameAttr(), {opRef});
}

//
// SymbolReferenceMap
//

mlir::Operation* ELF::SymbolReferenceMap::lookupSymbol(mlir::SymbolRefAttr symRef) {
    // convention for symbols naming: @section_name::@symbol_name
    // @section_name can be retrieved via SymbolRefAttr::getRootReference()
    // and @symbol_name from SymbolRefAttr::getLeafReference()
    // however there are some exceptions from this rule, having a @symbol_name directly under ElfMainOp

    VPUX_THROW_UNLESS(symRef, "Symbol reference is null");
    auto symbolRoot = symRef.getRootReference();
    auto symbolLeaf = symRef.getLeafReference();
    auto sectionSymbolContainerIt = _sectionSymbolContainers.find(symbolRoot);
    if (sectionSymbolContainerIt == _sectionSymbolContainers.end()) {
        auto symbolRootOp = _elfMainSymbolTable.lookup(symbolRoot);
        VPUX_THROW_UNLESS(symbolRootOp, "Symbol {0} not found under elfMain", symbolRoot.str());

        if (!symbolRootOp->hasTrait<mlir::OpTrait::SymbolContainer>() || symbolRoot == symbolLeaf) {
            return symbolRootOp;
        }

        auto insertRes = _sectionSymbolContainers.insert({symbolRoot, mlir::SymbolTable(symbolRootOp)});
        sectionSymbolContainerIt = insertRes.first;
    }

    auto symbolOp = sectionSymbolContainerIt->second.lookup(symbolLeaf);
    VPUX_THROW_UNLESS(symbolOp, "No op found for symbol {0}::{1}", symbolRoot, symbolLeaf);

    return symbolOp;
}

void ELF::SymbolReferenceMap::walkAllSymbols() {
    auto elfOp = _elfMainSymbolTable.getOp();

    for (mlir::Region& region : elfOp->getRegions()) {
        for (mlir::Block& block : region) {
            for (mlir::Operation& nestedOp : block) {
                if (nestedOp.hasTrait<mlir::OpTrait::SymbolContainer>()) {
                    auto symbol = mlir::cast<mlir::SymbolOpInterface>(&nestedOp);
                    auto insertRes =
                            _sectionSymbolContainers.insert({symbol.getNameAttr(), mlir::SymbolTable(&nestedOp)});

                    VPUX_THROW_UNLESS(insertRes.second, "ElfMain expected to contain uniquely named symbols {0}",
                                      elfOp);
                }
            }
        }
    }
}

//
// Platform Information
//

namespace {
const std::unordered_map<VPU::ArchKind, elf::platform::ArchKind> vpuToElfArchEnumMap = {
        {VPU::ArchKind::UNKNOWN, elf::platform::ArchKind::UNKNOWN},
        {VPU::ArchKind::NPU30XX, elf::platform::ArchKind::VPUX30XX},
        {VPU::ArchKind::NPU37XX, elf::platform::ArchKind::VPUX37XX},
        {VPU::ArchKind::NPU40XX, elf::platform::ArchKind::VPUX40XX}};
}  // namespace

elf::platform::ArchKind vpux::ELF::mapVpuArchKindToElfArchKind(const VPU::ArchKind& archKind) {
    return vpuToElfArchEnumMap.at(archKind);
}