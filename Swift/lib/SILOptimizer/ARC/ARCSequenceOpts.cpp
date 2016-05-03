//===--- ARCSequenceOpts.cpp ----------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#define DEBUG_TYPE "arc-sequence-opts"
#include "swift/SILOptimizer/PassManager/Passes.h"
#include "ARCSequenceOpts.h"
#include "swift/Basic/Fallthrough.h"
#include "swift/SIL/SILBuilder.h"
#include "swift/SIL/SILVisitor.h"
#include "swift/SILOptimizer/Utils/Local.h"
#include "swift/SILOptimizer/Utils/LoopUtils.h"
#include "swift/SILOptimizer/PassManager/Transforms.h"
#include "swift/SILOptimizer/Analysis/ARCAnalysis.h"
#include "swift/SILOptimizer/Analysis/AliasAnalysis.h"
#include "swift/SILOptimizer/Analysis/ProgramTerminationAnalysis.h"
#include "swift/SILOptimizer/Analysis/PostOrderAnalysis.h"
#include "swift/SILOptimizer/Analysis/RCIdentityAnalysis.h"
#include "swift/SILOptimizer/Analysis/LoopRegionAnalysis.h"
#include "swift/SILOptimizer/Analysis/LoopAnalysis.h"
#include "llvm/ADT/PointerUnion.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/CommandLine.h"

using namespace swift;

STATISTIC(NumRefCountOpsMoved, "Total number of increments moved");
STATISTIC(NumRefCountOpsRemoved, "Total number of increments removed");

llvm::cl::opt<bool> EnableLoopARC("enable-loop-arc", llvm::cl::init(true));

//===----------------------------------------------------------------------===//
//                                Code Motion
//===----------------------------------------------------------------------===//

/// Creates an increment on \p Ptr at insertion point \p InsertPt that creates a
/// strong_retain if \p Ptr has reference semantics itself or a retain_value if
/// \p Ptr is a non-trivial value without reference-semantics.
static SILInstruction *createIncrement(SILValue Ptr, SILInstruction *InsertPt) {
  // Set up the builder we use to insert at our insertion point.
  SILBuilder B(InsertPt);
  auto Loc = RegularLocation(SourceLoc());

  // If Ptr is refcounted itself, create the strong_retain and
  // return.
  if (Ptr->getType().isReferenceCounted(B.getModule()))
    return B.createStrongRetain(Loc, Ptr, Atomicity::Atomic);

  // Otherwise, create the retain_value.
  return B.createRetainValue(Loc, Ptr, Atomicity::Atomic);
}

/// Creates a decrement on \p Ptr at insertion point \p InsertPt that creates a
/// strong_release if \p Ptr has reference semantics itself or a release_value
/// if \p Ptr is a non-trivial value without reference-semantics.
static SILInstruction *createDecrement(SILValue Ptr, SILInstruction *InsertPt) {
  // Setup the builder we will use to insert at our insertion point.
  SILBuilder B(InsertPt);
  auto Loc = RegularLocation(SourceLoc());

  // If Ptr has reference semantics itself, create a strong_release.
  if (Ptr->getType().isReferenceCounted(B.getModule()))
    return B.createStrongRelease(Loc, Ptr, Atomicity::Atomic);

  // Otherwise create a release value.
  return B.createReleaseValue(Loc, Ptr, Atomicity::Atomic);
}

// This routine takes in the ARCMatchingSet \p MatchSet and inserts new
// increments, decrements at the insertion points and adds the old increment,
// decrements to the delete list. Sets changed to true if anything was moved or
// deleted.
void ARCPairingContext::optimizeMatchingSet(
    ARCMatchingSet &MatchSet, llvm::SmallVectorImpl<SILInstruction *> &NewInsts,
    llvm::SmallVectorImpl<SILInstruction *> &DeadInsts) {
  DEBUG(llvm::dbgs() << "**** Optimizing Matching Set ****\n");

  // Insert the new increments.
  for (SILInstruction *InsertPt : MatchSet.IncrementInsertPts) {
    if (!InsertPt) {
      DEBUG(llvm::dbgs() << "    No insertion point, not inserting increment "
            "into new position.\n");
      continue;
    }

    MadeChange = true;
    SILInstruction *NewIncrement = createIncrement(MatchSet.Ptr, InsertPt);
    NewInsts.push_back(NewIncrement);
    DEBUG(llvm::dbgs() << "    Inserting new increment: " << *NewIncrement
                       << "        At insertion point: " << *InsertPt);
    ++NumRefCountOpsMoved;
  }

  // Insert the new decrements.
  for (SILInstruction *InsertPt : MatchSet.DecrementInsertPts) {
    if (!InsertPt) {
      DEBUG(llvm::dbgs() << "    No insertion point, not inserting decrement "
            "into its new position.\n");
      continue;
    }

    MadeChange = true;
    SILInstruction *NewDecrement = createDecrement(MatchSet.Ptr, InsertPt);
    NewInsts.push_back(NewDecrement);
    DEBUG(llvm::dbgs() << "    Inserting new NewDecrement: " << *NewDecrement
                       << "        At insertion point: " << *InsertPt);
    ++NumRefCountOpsMoved;
  }

  // Add the old increments to the delete list.
  for (SILInstruction *Increment : MatchSet.Increments) {
    MadeChange = true;
    DEBUG(llvm::dbgs() << "    Deleting increment: " << *Increment);
    DeadInsts.push_back(Increment);
    ++NumRefCountOpsRemoved;
  }

  // Add the old decrements to the delete list.
  for (SILInstruction *Decrement : MatchSet.Decrements) {
    MadeChange = true;
    DEBUG(llvm::dbgs() << "    Deleting decrement: " << *Decrement);
    DeadInsts.push_back(Decrement);
    ++NumRefCountOpsRemoved;
  }
}

bool ARCPairingContext::performMatching(
    llvm::SmallVectorImpl<SILInstruction *> &NewInsts,
    llvm::SmallVectorImpl<SILInstruction *> &DeadInsts) {
  bool MatchedPair = false;

  DEBUG(llvm::dbgs() << "**** Computing ARC Matching Sets for " << F.getName()
                     << " ****\n");

  /// For each increment that we matched to a decrement, try to match it to a
  /// decrement -> increment pair.
  for (auto Pair : IncToDecStateMap) {
    if (!Pair.hasValue())
      continue;

    SILInstruction *Increment = Pair->first;
    if (!Increment)
      continue; // blotted

    DEBUG(llvm::dbgs() << "Constructing Matching Set For: " << *Increment);
    ARCMatchingSetBuilder Builder(DecToIncStateMap, IncToDecStateMap, RCIA);
    Builder.init(Increment);
    if (Builder.matchUpIncDecSetsForPtr()) {
      MatchedPair |= Builder.matchedPair();
      auto &Set = Builder.getResult();
      for (auto *I : Set.Increments)
        IncToDecStateMap.blot(I);
      for (auto *I : Set.Decrements)
        DecToIncStateMap.blot(I);

      // Add the Set to the callback. *NOTE* No instruction destruction can
      // happen here since we may remove instructions that are insertion points
      // for other instructions.
      optimizeMatchingSet(Set, NewInsts, DeadInsts);
    }
  }

  return MatchedPair;
}

//===----------------------------------------------------------------------===//
//                                  Loop ARC
//===----------------------------------------------------------------------===//

void LoopARCPairingContext::runOnLoop(SILLoop *L) {
  auto *Region = LRFI->getRegion(L);
  if (processRegion(Region, false, false)) {
    // We do not recompute for now since we only look at the top function level
    // for post dominating releases.
    processRegion(Region, true, false);
  }

  // Now that we have finished processing the loop, summarize the loop.
  Evaluator.summarizeLoop(Region);
}

void LoopARCPairingContext::runOnFunction(SILFunction *F) {
  if (processRegion(LRFI->getTopLevelRegion(), false, false)) {
    // We recompute the final post dom release since we may have moved the final
    // post dominated releases.
    processRegion(LRFI->getTopLevelRegion(), true, true);
  }
}

bool LoopARCPairingContext::processRegion(const LoopRegion *Region,
                                          bool FreezePostDomReleases,
                                          bool RecomputePostDomReleases) {
  llvm::SmallVector<SILInstruction *, 8> NewInsts;
  llvm::SmallVector<SILInstruction *, 8> DeadInsts;

  // We have already summarized all subloops of this loop. Now summarize our
  // blocks so that we only visit interesting instructions.
  Evaluator.summarizeSubregionBlocks(Region);

  bool MadeChange = false;
  bool NestingDetected = false;
  bool MatchedPair = false;

  do {
    NestingDetected = Evaluator.runOnLoop(Region, FreezePostDomReleases,
                                          RecomputePostDomReleases);
    MatchedPair = Context.performMatching(NewInsts, DeadInsts);

    if (!NewInsts.empty()) {
      DEBUG(llvm::dbgs() << "Adding new interesting insts!\n");
      do {
        auto *I = NewInsts.pop_back_val();
        DEBUG(llvm::dbgs() << "    " << *I);
        Evaluator.addInterestingInst(I);
      } while (!NewInsts.empty());
    }

    if (!DeadInsts.empty()) {
      DEBUG(llvm::dbgs() << "Removing dead interesting insts!\n");
      do {
        SILInstruction *I = DeadInsts.pop_back_val();
        DEBUG(llvm::dbgs() << "    " << *I);
        Evaluator.removeInterestingInst(I);
        I->eraseFromParent();
      } while (!DeadInsts.empty());
    }

    MadeChange |= MatchedPair;
    Evaluator.clearLoopState(Region);
    Context.DecToIncStateMap.clear();
    Context.IncToDecStateMap.clear();
    Evaluator.clearSetFactory();

    // This ensures we only ever recompute post dominating releases on the first
    // iteration.
    RecomputePostDomReleases = false;
  } while (NestingDetected && MatchedPair);

  return MadeChange;
}

//===----------------------------------------------------------------------===//
//                             Non Loop Optimizer
//===----------------------------------------------------------------------===//

static bool
processFunctionWithoutLoopSupport(SILFunction &F, bool FreezePostDomReleases,
                                  AliasAnalysis *AA, PostOrderAnalysis *POTA,
                                  RCIdentityFunctionInfo *RCIA,
                                  ProgramTerminationFunctionInfo *PTFI) {
  // GlobalARCOpts seems to be taking up a lot of compile time when running on
  // globalinit_func. Since that is not *that* interesting from an ARC
  // perspective (i.e. no ref count operations in a loop), disable it on such
  // functions temporarily in order to unblock others. This should be removed.
  if (F.getName().startswith("globalinit_"))
    return false;

  DEBUG(llvm::dbgs() << "***** Processing " << F.getName() << " *****\n");

  bool Changed = false;
  BlockARCPairingContext Context(F, AA, POTA, RCIA, PTFI);
  // Until we do not remove any instructions or have nested increments,
  // decrements...
  while (true) {
    // Compute matching sets of increments, decrements, and their insertion
    // points.
    //
    // We need to blot pointers we remove after processing an individual pointer
    // so we don't process pairs after we have paired them up. Thus we pass in a
    // lambda that performs the work for us.
    bool ShouldRunAgain = Context.run(FreezePostDomReleases);

    Changed |= Context.madeChange();

    // If we did not remove any instructions or have any nested increments, do
    // not perform another iteration.
    if (!ShouldRunAgain)
      break;

    // Otherwise, perform another iteration.
    DEBUG(llvm::dbgs() << "\n<<< Made a Change! Reprocessing Function! >>>\n");
  }

  DEBUG(llvm::dbgs() << "\n");

  // Return true if we moved or deleted any instructions.
  return Changed;
}

//===----------------------------------------------------------------------===//
//                               Loop Optimizer
//===----------------------------------------------------------------------===//

static bool processFunctionWithLoopSupport(
    SILFunction &F, AliasAnalysis *AA, PostOrderAnalysis *POTA,
    LoopRegionFunctionInfo *LRFI, SILLoopInfo *LI, RCIdentityFunctionInfo *RCFI,
    ProgramTerminationFunctionInfo *PTFI) {
  // GlobalARCOpts seems to be taking up a lot of compile time when running on
  // globalinit_func. Since that is not *that* interesting from an ARC
  // perspective (i.e. no ref count operations in a loop), disable it on such
  // functions temporarily in order to unblock others. This should be removed.
  if (F.getName().startswith("globalinit_"))
    return false;

  DEBUG(llvm::dbgs() << "***** Processing " << F.getName() << " *****\n");

  LoopARCPairingContext Context(F, AA, LRFI, LI, RCFI, PTFI);
  return Context.process();
}

//===----------------------------------------------------------------------===//
//                              Top Level Driver
//===----------------------------------------------------------------------===//

namespace {
class ARCSequenceOpts : public SILFunctionTransform {
  /// The entry point to the transformation.
  void run() override {
    auto *F = getFunction();

    // If ARC optimizations are disabled, don't optimize anything and bail.
    if (!getOptions().EnableARCOptimizations)
      return;

    if (!EnableLoopARC) {
      auto *AA = getAnalysis<AliasAnalysis>();
      auto *POTA = getAnalysis<PostOrderAnalysis>();
      auto *RCFI = getAnalysis<RCIdentityAnalysis>()->get(F);
      ProgramTerminationFunctionInfo PTFI(F);

      if (processFunctionWithoutLoopSupport(*F, false, AA, POTA, RCFI, &PTFI)) {
        processFunctionWithoutLoopSupport(*F, true, AA, POTA, RCFI, &PTFI);
        invalidateAnalysis(SILAnalysis::InvalidationKind::CallsAndInstructions);
      }
      return;
    }

    auto *LA = getAnalysis<SILLoopAnalysis>();
    auto *LI = LA->get(F);
    auto *DA = getAnalysis<DominanceAnalysis>();
    auto *DI = DA->get(F);

    // Canonicalize the loops, invalidating if we need to.
    if (canonicalizeAllLoops(DI, LI)) {
      // We preserve loop info and the dominator tree.
      DA->lockInvalidation();
      LA->lockInvalidation();
      PM->invalidateAnalysis(F, SILAnalysis::InvalidationKind::FunctionBody);
      DA->unlockInvalidation();
      LA->unlockInvalidation();
    }

    auto *AA = getAnalysis<AliasAnalysis>();
    auto *POTA = getAnalysis<PostOrderAnalysis>();
    auto *RCFI = getAnalysis<RCIdentityAnalysis>()->get(F);
    auto *LRFI = getAnalysis<LoopRegionAnalysis>()->get(F);
    ProgramTerminationFunctionInfo PTFI(F);

    if (processFunctionWithLoopSupport(*F, AA, POTA, LRFI, LI, RCFI, &PTFI)) {
      invalidateAnalysis(SILAnalysis::InvalidationKind::CallsAndInstructions);
    }
  }

  StringRef getName() override { return "ARC Sequence Opts"; }
};

} // end anonymous namespace


SILTransform *swift::createARCSequenceOpts() {
  return new ARCSequenceOpts();
}