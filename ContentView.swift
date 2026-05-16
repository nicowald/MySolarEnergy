//
//  ContentView.swift
//  MSE Watch App
//
//  Created by Nico Wald on 2026-05-16.
//

import SwiftUI
import Combine

// MARK: - Model
struct SensorData: Codable {
   let address: String
   let type: String
   let accessMode: String
   let text: String
   let unit: String
   let value: Int
   
   static var placeholder: SensorData {
      SensorData(
         address: "",
         type: "",
         accessMode: "",
         text: "",
         unit: "",
         value: 0
      )
   }
}

// MARK: - ViewModel
final class FEMSClient: ObservableObject {
   static var shared: FEMSClient?
   
   @Published var batterySoC: SensorData
   @Published var batteryCapacity: SensorData
   @Published var consumption: SensorData
   @Published var production: SensorData
   @Published var grid: SensorData
   @Published var batteryPower: SensorData
   @Published var gridBuySum: SensorData
   @Published var gridSellSum: SensorData
   @Published var consumptionSum: SensorData
   @Published var yearsToGo: Double
   @Published var currentSaving: Double
   @Published var savingOffset: Double {
      didSet {
         UserDefaults.standard.set(savingOffset, forKey: "savingOffset")
      }
   }
   @Published var customDateComponents: DateComponents {
      didSet {
         if let data = try? PropertyListEncoder().encode(customDateComponents) {
            UserDefaults.standard.set(data, forKey: "customDateComponents")
         }
      }
   }
   @Published var pricePerKWh: Double {
      didSet {
         UserDefaults.standard.set(pricePerKWh, forKey: "pricePerKWh")
      }
   }
   @Published var ipAddress: String {
      didSet {
         UserDefaults.standard.set(ipAddress, forKey: "ipAddress")
      }
   }
   @Published var totalCost: Double {
      didSet {
         UserDefaults.standard.set(totalCost, forKey: "totalCost")
      }
   }
   @Published var lastSavingOffsetDate: Date? {
      didSet {
         if let date = lastSavingOffsetDate {
            UserDefaults.standard.set(date, forKey: "lastSavingOffsetDate")
         } else {
            UserDefaults.standard.removeObject(forKey: "lastSavingOffsetDate")
         }
      }
   }
   
   private var timerSlow: Timer?
   private var timerFast: Timer?
   
   init() {
      batterySoC = .placeholder
      batteryCapacity = .placeholder
      consumption = .placeholder
      production = .placeholder
      grid = .placeholder
      batteryPower = .placeholder
      gridBuySum = .placeholder
      gridSellSum = .placeholder
      consumptionSum = .placeholder
      yearsToGo = 0
      currentSaving = 0
      savingOffset = UserDefaults.standard.double(forKey: "savingOffset")
      if let data = UserDefaults.standard.data(forKey: "customDateComponents"),
         let decoded = try? PropertyListDecoder().decode(DateComponents.self, from: data) {
         self.customDateComponents = decoded
      } else {
         self.customDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
      }
      pricePerKWh = UserDefaults.standard.double(forKey: "pricePerKWh")
      ipAddress = UserDefaults.standard.string(forKey: "ipAddress") ?? "0.0.0.0"
      let storedTotalCost = UserDefaults.standard.double(forKey: "totalCost")
      totalCost = storedTotalCost > 0 ? storedTotalCost : 0
      lastSavingOffsetDate = UserDefaults.standard.object(forKey: "lastSavingOffsetDate") as? Date
      currentSaving = savingOffset
      FEMSClient.shared = self
      startPolling()
   }
   
   func startPolling() {
      fetchBattery()
      fetchConsumption()
      fetchProduction()
      fetchGid()
      timerSlow = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
         self?.fetchBattery()
      }
      timerSlow?.tolerance = 10.0
      timerFast = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
         self?.fetchConsumption()
         self?.fetchProduction()
         self?.fetchGid()
      }
      timerFast?.tolerance = 1.0
   }
   
   func stopPolling() {
      timerSlow?.invalidate()
      timerSlow = nil
      timerFast?.invalidate()
      timerFast = nil
   }
   
   func fetchConsumption() {
      Task {
         if let sensor = await fetchEndpoint(endpoint: "ConsumptionActivePower") {
            await MainActor.run {
               self.consumption = sensor
            }
         }
      }
      Task {
         if let sensor = await fetchEndpoint(endpoint: "EssDischargePower") {
            await MainActor.run {
               self.batteryPower = sensor
            }
         }
      }
      
      if self.consumptionSum.value > 0 && self.gridBuySum.value > 0 && self.gridSellSum.value > 0 {
         let calendar = Calendar.current
         if let customDate = calendar.date(from: self.customDateComponents) {
            let kWHPriceSell = 0.082
            
            let totalSaved = Double(self.consumptionSum.value - self.gridBuySum.value)
            let kWHPriceBuy_1 = 0.312
            let gridBuy_1 = 4614.7
            
            let totalSavedBuy = (totalSaved - gridBuy_1) * pricePerKWh + gridBuy_1 * kWHPriceBuy_1
            let totalEarned = ((totalSavedBuy+Double(self.gridSellSum.value)*kWHPriceSell)/1000.0)
            
            let uptime_months = -1.0 * customDate.timeIntervalSinceNow / 60.0 / 60.0 / 24.0 / 30.0
            let earnedPerMonth = totalEarned / uptime_months
            
            let yearsToGo = (self.totalCost - totalEarned) / earnedPerMonth / 12.0
            self.yearsToGo = max(yearsToGo, 0)
            
            self.currentSaving = totalEarned
         }
      }
   }
   
   func resetSavingOffset() {
      self.savingOffset = self.currentSaving
      self.lastSavingOffsetDate = Date()
   }
   
   func fetchGid() {
      Task {
         if let sensor = await fetchEndpoint(endpoint: "GridActivePower") {
            await MainActor.run {
               self.grid = sensor
            }
         }
      }
   }
   
   func fetchProduction() {
      Task {
         if let sensor = await fetchEndpoint(endpoint: "ProductionActivePower") {
            await MainActor.run {
               self.production = sensor
            }
         }
      }
   }
   
   func fetchBattery() {
      Task {
         if let sensor = await fetchEndpoint(endpoint: "EssSoc") {
            await MainActor.run {
               self.batterySoC = sensor
               let appGroupID = "group.com.SubtleSoft.mse"
               DispatchQueue.main.async {
                  if let defaults = UserDefaults(suiteName: appGroupID) {
                     defaults.set(sensor.value, forKey: "batterySoC")
                  }
               }
            }
         }
      }
      Task {
         if let sensor = await fetchEndpoint(endpoint: "EssCapacity") {
            await MainActor.run {
               self.batteryCapacity = sensor
            }
         }
      }
      Task {
         if let sensor = await fetchEndpoint(endpoint: "GridBuyActiveEnergy") {
            await MainActor.run {
               self.gridBuySum = sensor
            }
         }
      }
      Task {
         if let sensor = await fetchEndpoint(endpoint: "GridSellActiveEnergy") {
            await MainActor.run {
               self.gridSellSum = sensor
            }
         }
      }
      Task {
         if let sensor = await fetchEndpoint(endpoint: "ConsumptionActiveEnergy") {
            await MainActor.run {
               self.consumptionSum = sensor
            }
         }
      }
   }
   
   func fetchEndpoint(endpoint: String) async -> SensorData? {
      guard let request = getRequest(endpoint: endpoint) else { return nil }
      
      do {
         let (data, _) = try await URLSession.shared.data(for: request)
         return try JSONDecoder().decode(SensorData.self, from: data)
      } catch {
         print("Error: \(error)")
         return nil
      }
   }
   
   private func getRequest(endpoint: String) -> URLRequest? {
      guard let url = URL(string: "http://\(ipAddress)/rest/channel/_sum/\(endpoint)") else {return nil}
      var request = URLRequest(url: url)
      let credentials = "x:user".data(using: .utf8)!.base64EncodedString()
      request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
      return request
   }
   
   deinit {
      stopPolling()
   }
}

// MARK: - View

struct ContentView: View {
   @StateObject private var client = FEMSClient()
   @State private var selectedTab = 1 // Default to MainView (index 1)
   
   var body: some View {
      ZStack {
         LinearGradient(
            gradient: Gradient(colors: [Color(red: 0.2, green: 0.3, blue: 0.3), // hellblau
                                        Color(red: 0.4, green: 0.4, blue: 0.3)]), // hellgelb
            startPoint: .topLeading,
            endPoint: .bottomTrailing
         )
         .ignoresSafeArea()
         TabView(selection: $selectedTab) {
            SettingsView(client: client)
               .tag(0)
            MainView(client: client)
               .tag(1)
            DetailView(client: client)
               .tag(2)
            BreakEvenView(client: client)
               .tag(3)
         }
         .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
         .onAppear {
             if client.ipAddress == "0.0.0.0" {
                 selectedTab = 0 // Start with SettingsView if IP not configured
             }
         }
#if os(iOS)
         .padding(40)
#endif
      }
   }
}

struct MainView: View {
   @ObservedObject var client = FEMSClient()
   
   var body: some View {
      VStack {
         #if os(iOS)
         Spacer()
         Spacer()
         #endif
         HStack {
            Text("🔌")
               .font(mainIconFont())
            Spacer()
            Text("\(formatSigned(client.consumption.value, false, "W"))")
               .font(mainValueFont())
               .multilineTextAlignment(.trailing)
         }
         Spacer()
         Text("=")
         HStack {
            Text("☀️")
               .font(mainIconFont())
            Spacer()
            Text("\(formatSigned(client.production.value, false, "W"))")
               .font(mainValueFont())
               .multilineTextAlignment(.trailing)
         }
         Spacer()
         HStack {
            Text("🔋")
               .font(mainIconFont())
               .layoutPriority(5)
            VStack {
               Text("\(client.batterySoC.value) %")
                  .font(mainValueFont())
                  .frame(alignment: .leading)
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
                  .padding(-4)
               Text("\(formatSigned(client.batteryCapacity.value * client.batterySoC.value / 100, false, "Wh"))")
                  .font(mainValueFont())
                  .frame(alignment: .leading)
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
                  .padding(-4)
            }
            .layoutPriority(2)
            Spacer()
            Text("\(formatSigned(client.batteryPower.value, true, "W"))")
               .font(mainValueFont())
               .lineLimit(1)
               .layoutPriority(10)
         }
         Spacer()
         HStack {
            Text("⚡️")
               .font(mainIconFont())
            Spacer()
            Text("\(formatSigned(client.grid.value, true, "W"))")
               .foregroundColor(client.grid.value <= 0 ? .green : .red)
               .font(mainValueFont())
               .multilineTextAlignment(.trailing)
         }
         #if os(iOS)
         Spacer()
         Spacer()
         #endif
      }
      .padding(.horizontal, 3)
   }
   
   private func mainIconFont() -> Font {
      #if os(iOS)
      return .system(size: 60)
      #else
      return .title2
      #endif
   }
   
   private func mainValueFont() -> Font {
      #if os(iOS)
      return .system(size: 28)
      #else
      return .title3
      #endif
   }
}

struct DetailView: View {
   @ObservedObject var client = FEMSClient()
   
   var body: some View {
      VStack {
         Text("Savings")
            .font(.headline)
         HStack {
            Text("Total:")
               .font(.body)
            Text("\(client.currentSaving.formatted(.number.precision(.fractionLength(2)))) €")
               .font(.subheadline)
               .lineLimit(1)
               .minimumScaleFactor(0.7)
         }
         Divider()
         let saving = client.currentSaving - client.savingOffset
         Text("Current: \(saving.formatted(.number.precision(.fractionLength(2)))) €")
            .font(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .onTapGesture {
               client.resetSavingOffset()
            }
         Text("Tap to reset current")
            .font(.footnote)
         if let resetDate = client.lastSavingOffsetDate {
            Text("Last reset: \(resetDate.formatted(date: .abbreviated, time: .omitted))")
               .font(.footnote)
         }

   }
      .padding(.horizontal, 3)
   }
}

struct BreakEvenView: View {
   @ObservedObject var client = FEMSClient()
   
   var body: some View {
      VStack {
         Text("Break even")
            .font(.headline)
         let years = Int(client.yearsToGo)
         let months = Int((client.yearsToGo - Double(years)) * 12.0)
         let days = Int(((client.yearsToGo - Double(years) - Double(months) / 12.0)) * 12.0 * 30.0)
         Text("\(years) years")
            .font(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
         Text("\(months) months")
            .font(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
         Text("\(days) days")
            .font(.body)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
      }
      .padding(.horizontal, 3)
   }
}

struct SettingsView: View {
   @ObservedObject var client: FEMSClient
   
   var body: some View {
      ScrollView{
         VStack(spacing: 0) {
            Section(header: Text("FEMS IP")) {
               TextField("", text: $client.ipAddress)
            }
            Divider()
               .padding(.vertical, 8)
            
            Section(header: Text("€ Cost per kWh")) {
               TextField("0", value: $client.pricePerKWh, format: .number.precision(.fractionLength(3)))
            }
            Divider()
               .padding(.vertical, 8)
            
            Section(header: Text("Operation Start")) {
               DatePicker(
                  "",
                  selection: Binding<Date>(
                     get: {
                        Calendar.current.date(from: client.customDateComponents) ?? Date()
                     },
                     set: {
                        client.customDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: $0)
                     }
                  ),
                  in: dateRange,
                  displayedComponents: .date
               )
               .frame(height: 80)
               .focusable(false)
            }
            Divider()
               .padding(.vertical, 8)
            
            Section(header: Text("€ System Cost")) {
               TextField("0", value: $client.totalCost, format: .number.precision(.fractionLength(2)))
            }
         }
         .padding(.horizontal, 3)
      }
   }
   
   private var dateRange: ClosedRange<Date> {
      let calendar = Calendar.current
      let minDate = calendar.date(from: DateComponents(year: 2011, month: 1, day: 1))!
      let maxDate = calendar.date(byAdding: .year, value: 1, to: Date())!
      return minDate...maxDate
   }
}

func formatSigned(_ value: Int, _ sign: Bool, _ unit: String) -> String {
   let formatter = NumberFormatter()
   formatter.numberStyle = .decimal
   if sign {
      formatter.positivePrefix = "+"
      formatter.negativePrefix = "−" // or just use "-"
   }
   formatter.minimumFractionDigits = 0
   formatter.maximumFractionDigits = 0
   
   var outValue = Double(value)
   var outUnit = unit
   if abs(value) >= 1000 {
      outValue = Double(value) / 1000.0
      outUnit = "k" + unit
      formatter.minimumFractionDigits = 1
      formatter.maximumFractionDigits = 1
   }
   return (formatter.string(from: NSNumber(value: outValue)) ?? "\(outValue)") + " " + outUnit
}

#Preview {
   ContentView()
}
