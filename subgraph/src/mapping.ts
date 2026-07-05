import { BovineAdded as BovineAddedEvent, VaccineAdded as VaccineAddedEvent, MovementAdded as MovementAddedEvent, FeedAdded as FeedAddedEvent, HealthExamAdded as HealthExamAddedEvent, AbattoirProcessAdded as AbattoirProcessAddedEvent } from "../generated/BovineTracking/BovineTracking"
import { Transfer as NFTTransferEvent } from "../generated/BovineNFT/BovineNFT"
import { Bovine, Vaccine, Movement, Feed, HealthExam, AbattoirProcess, NFTTransfer } from "../generated/schema"

export function handleBovineAdded(event: BovineAddedEvent): void {
  let bovine = new Bovine(event.params.id.toString())
  bovine.name = event.params.name
  bovine.age = event.params.age
  bovine.breed = event.params.breed
  bovine.location = event.params.location
  bovine.owner = event.params.owner
  bovine.save()
}

export function handleVaccineAdded(event: VaccineAddedEvent): void {
  let vaccineId = event.params.bovineId.toString() + "-" + "vaccine-" + event.transaction.index.toString()
  let vaccine = new Vaccine(vaccineId)
  vaccine.bovine = event.params.bovineId.toString()
  vaccine.name = event.params.name
  vaccine.date = event.params.date
  vaccine.save()
}

export function handleMovementAdded(event: MovementAddedEvent): void {
  let movementId = event.params.bovineId.toString() + "-" + "movement-" + event.transaction.index.toString()
  let movement = new Movement(movementId)
  movement.bovine = event.params.bovineId.toString()
  movement.fromLocation = event.params.fromLocation
  movement.toLocation = event.params.toLocation
  movement.date = event.params.date
  movement.save()
}

export function handleFeedAdded(event: FeedAddedEvent): void {
  let feedId = event.params.bovineId.toString() + "-" + "feed-" + event.transaction.index.toString()
  let feed = new Feed(feedId)
  feed.bovine = event.params.bovineId.toString()
  feed.foodType = event.params.foodType
  feed.origin = event.params.origin
  feed.quantity = event.params.quantity
  feed.date = event.params.date
  feed.save()
}

export function handleHealthExamAdded(event: HealthExamAddedEvent): void {
  let examId = event.params.bovineId.toString() + "-" + "exam-" + event.transaction.index.toString()
  let exam = new HealthExam(examId)
  exam.bovine = event.params.bovineId.toString()
  exam.examType = event.params.examType
  exam.result = event.params.result
  exam.date = event.params.date
  exam.save()
}

export function handleAbattoirProcessAdded(event: AbattoirProcessAddedEvent): void {
  let processId = event.params.bovineId.toString() + "-" + "process-" + event.transaction.index.toString()
  let process = new AbattoirProcess(processId)
  process.bovine = event.params.bovineId.toString()
  process.abattoir = event.params.abattoir
  process.abattoirDate = event.params.abattoirDate
  process.processing = event.params.processing
  process.date = event.params.date
  process.save()
}

export function handleNFTTransfer(event: NFTTransferEvent): void {
  let transfer = new NFTTransfer(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  )
  transfer.from = event.params.from
  transfer.to = event.params.to
  transfer.tokenId = event.params.tokenId
  transfer.timestamp = event.block.timestamp
  transfer.blockNumber = event.block.number
  transfer.save()
}
