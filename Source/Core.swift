//  Core.swift
//  Eureka ( https://github.com/xmartlabs/Eureka )
//
//  Copyright (c) 2015 Xmartlabs ( http://xmartlabs.com )
//
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import UIKit

//MARK: Controller Protocols

public protocol RowControllerType : NSObjectProtocol {
    var completionCallback : ((UIViewController) -> ())? { get set }
}

public protocol TypedRowControllerType : RowControllerType {
    typealias RowValue: Equatable
    var row : RowOf<Self.RowValue>! { get set }
}

public protocol FormDelegate : class {
    func sectionsHaveBeenAdded(sections: [Section], atIndexes: NSIndexSet)
    func sectionsHaveBeenRemoved(sections: [Section], atIndexes: NSIndexSet)
    func sectionsHaveBeenReplaced(oldSections oldSections:[Section], newSections: [Section], atIndexes: NSIndexSet)
    func rowsHaveBeenAdded(rows: [BaseRow], atIndexPaths:[NSIndexPath])
    func rowsHaveBeenRemoved(rows: [BaseRow], atIndexPaths:[NSIndexPath])
    func rowsHaveBeenReplaced(oldRows oldRows:[BaseRow], newRows: [BaseRow], atIndexPaths: [NSIndexPath])
    func rowValueHasBeenChanged(row: BaseRow, oldValue: Any, newValue: Any)
}

//MARK: Header Footer Protocols

public protocol HeaderFooterViewRepresentable {
    func viewForSection(section: Section, type: HeaderFooterType, controller: FormViewController) -> UIView?
    var title: String? { get set }
    var height: CGFloat? { get set }
}

//MARK: Row Protocols

public protocol Taggable : AnyObject {
    var tag: String? { get set }
}

public protocol BaseRowType : Taggable {
    
    var callbackOnChange: Any? { get set }
    var callbackCellOnSelection: Any? { get set }
    var callbackCellUpdate: Any? { get set }
    var callbackCellSetup: Any? { get set }
    
    
    var baseCell: BaseCell! { get }
    var section: Section? { get }
    
    var cellStyle : UITableViewCellStyle { get set }
    var title: String? { get set }
    func updateCell()
    func didSelect()
    
    init(tag: String?)
}

public protocol TypedRowType : BaseRowType {
    
    typealias Value : Equatable
    typealias Cell : BaseCell, CellType
    var cell : Self.Cell! { get }
    var value : Self.Value? { get set }
}

public protocol RowType : TypedRowType {
    init(_ tag: String?, _ initializer: (Self -> ()))
}

public protocol PresenterRowType: TypedRowType {
    
    typealias ProviderType : UIViewController, TypedRowControllerType
    var presentationMode: PresentationMode<ProviderType>? { get set }
    var onPresentCallback: ((FormViewController, ProviderType)->())? { get set }
}

//MARK: Cell Protocols

public protocol BaseCellType : class {
    
    var height : (()-> CGFloat)? { get }
    func setup()
    func update()
    func didSelect()
    func highlight()
    func unhighlight()
    func cellCanBecomeFirstResponder() -> Bool
    func cellBecomeFirstResponder() -> Bool
    func formViewController () -> FormViewController?
}


public protocol TypedCellType : BaseCellType {
    typealias Value : Equatable
    var row : RowOf<Self.Value>! { get set }
}

public protocol CellType: TypedCellType {}

//MARK: Form

public final class Form {

    public static var defaultNavigationOptions = RowNavigationOptions.Enabled.union(.SkipCanNotBecomeFirstResponderRow)
    public weak var delegate: FormDelegate?

    public init(){}
    
    public subscript(indexPath: NSIndexPath) -> BaseRow {
        return self[indexPath.section][indexPath.row]
    }
    
    public func rowByTag<T: Equatable>(tag: String) -> RowOf<T>? {
        let row: BaseRow? = rowByTag(tag)
        return row as? RowOf<T>
    }
    
    public func rowByTag<Row: RowType>(tag: String) -> Row? {
        let row: BaseRow? = rowByTag(tag)
        return row as? Row
    }
    
    public func rowByTag(tag: String) -> BaseRow? {
        return rowsByTag[tag]
    }
    
    public func sectionByTag(tag: String) -> Section? {
        return kvoWrapper._allSections.filter( { $0.tag == tag }).first
    }
    
    public func values(includeHidden includeHidden: Bool = false) -> [String: Any?]{
        if includeHidden {
            return allRows.filter({ $0.tag != nil })
                          .reduce([String: Any?]()) {
                               var result = $0
                               result[$1.tag!] = $1.baseValue
                               return result
                          }
        }
        return rows.filter({ $0.tag != nil })
                   .reduce([String: Any?]()) {
                        var result = $0
                        result[$1.tag!] = $1.baseValue
                        return result
                    }
    }
    
    public var rows: [BaseRow] { return flatMap { $0 } }
    public var allRows: [BaseRow] { return kvoWrapper._allSections.map({ $0.kvoWrapper._allRows }).flatMap { $0 } }
    
    
    //MARK: Private
    
    var rowObservers = [String: [ConditionType: [Taggable]]]()
    var rowsByTag = [String: BaseRow]()
    private lazy var kvoWrapper : KVOWrapper = { [unowned self] in return KVOWrapper(form: self) }()
}

extension Form : MutableCollectionType {
    
    // MARK: MutableCollectionType
    
    public var startIndex: Int { return 0 }
    public var endIndex: Int { return kvoWrapper.sections.count }
    public subscript (position: Int) -> Section {
        get { return kvoWrapper.sections[position] as! Section }
        set { kvoWrapper.sections[position] = newValue }
    }
}

extension Form : RangeReplaceableCollectionType {
    
    // MARK: RangeReplaceableCollectionType
    
    public func append(formSection: Section){
        kvoWrapper.sections.insertObject(formSection, atIndex: kvoWrapper.sections.count)
        kvoWrapper._allSections.append(formSection)
        formSection.wasAddedToForm(self)
    }

    public func appendContentsOf<S : SequenceType where S.Generator.Element == Section>(newElements: S) {
        kvoWrapper.sections.addObjectsFromArray(newElements.map { $0 })
        kvoWrapper._allSections.appendContentsOf(newElements)
        for section in newElements{
            section.wasAddedToForm(self)
        }
    }
    
    public func reserveCapacity(n: Int){}

    public func replaceRange<C : CollectionType where C.Generator.Element == Section>(subRange: Range<Int>, with newElements: C) {
        for (var i = subRange.startIndex; i < subRange.endIndex; i++) {
            if let section = kvoWrapper.sections.objectAtIndex(i) as? Section {
                section.willBeRemovedFromForm()
                kvoWrapper._allSections.removeAtIndex(kvoWrapper._allSections.indexOf(section)!)
            }
        }
        kvoWrapper.sections.replaceObjectsInRange(NSMakeRange(subRange.startIndex, subRange.endIndex - subRange.startIndex), withObjectsFromArray: newElements.map { $0 })
        for section in newElements{
            section.wasAddedToForm(self)
        }
    }
    
    public func removeAll(keepCapacity keepCapacity: Bool = false) {
        // not doing anything with capacity
        for section in kvoWrapper._allSections{
            section.willBeRemovedFromForm()
        }
        kvoWrapper.sections.removeAllObjects()
        kvoWrapper._allSections.removeAll()
    }
}

extension Form {
    
    // MARK: Private Helpers
    
    private class KVOWrapper : NSObject {
        dynamic var _sections = NSMutableArray()
        var sections : NSMutableArray { return mutableArrayValueForKey("_sections") }
        var _allSections = [Section]()
        weak var form: Form?
        
        init(form: Form){
            self.form = form
            super.init()
            addObserver(self, forKeyPath: "_sections", options: NSKeyValueObservingOptions.New.union(.Old), context:nil)
        }
        
        deinit { removeObserver(self, forKeyPath: "_sections") }
        
        override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
            
            let newSections = change?[NSKeyValueChangeNewKey] as? [Section] ?? []
            let oldSections = change?[NSKeyValueChangeOldKey] as? [Section] ?? []
            guard let delegateValue = form?.delegate, let keyPathValue = keyPath, let changeType = change?[NSKeyValueChangeKindKey] else { return }
            guard keyPathValue == "_sections" else { return }
            switch changeType.unsignedLongValue {
                case NSKeyValueChange.Setting.rawValue:
                    let indexSet = change![NSKeyValueChangeIndexesKey] as? NSIndexSet ?? NSIndexSet(index: 0)
                    delegateValue.sectionsHaveBeenAdded(newSections, atIndexes: indexSet)
                case NSKeyValueChange.Insertion.rawValue:
                    let indexSet = change![NSKeyValueChangeIndexesKey] as! NSIndexSet
                    delegateValue.sectionsHaveBeenAdded(newSections, atIndexes: indexSet)
                case NSKeyValueChange.Removal.rawValue:
                    let indexSet = change![NSKeyValueChangeIndexesKey] as! NSIndexSet
                    delegateValue.sectionsHaveBeenRemoved(oldSections, atIndexes: indexSet)
                case NSKeyValueChange.Replacement.rawValue:
                    let indexSet = change![NSKeyValueChangeIndexesKey] as! NSIndexSet
                    delegateValue.sectionsHaveBeenReplaced(oldSections: oldSections, newSections: newSections, atIndexes: indexSet)
                default:
                    assertionFailure()
            }
        }
    }
    
    func dictionaryValuesToEvaluatePredicate() -> [String: AnyObject] {
        return rowsByTag.reduce([String: AnyObject]()) {
            var result = $0
            result[$1.0] = $1.1.baseValue as? AnyObject ?? NSNull()
            return result
        }
    }
    
    private func addRowObservers(taggable: Taggable, rowTags: [String], type: ConditionType) {
        for rowTag in rowTags{
            if let _ = rowObservers[rowTag]?[type]{
                if !rowObservers[rowTag]![type]!.contains({ $0 === taggable }){
                    rowObservers[rowTag]?[type]!.append(taggable)
                }
            }
            else{
                rowObservers[rowTag] = Dictionary()
                rowObservers[rowTag]?[type] = [taggable]
            }
        }
    }
    
    private func removeRowObservers(taggable: Taggable, rows: [String], type: ConditionType) {
        for row in rows{
            guard var arr = rowObservers[row]?[type], let index = arr.indexOf({ $0 === taggable }) else { continue }
            arr.removeAtIndex(index)
        }
    }
    
    internal func nextRowForRow(currentRow: BaseRow) -> BaseRow? {
        let allRows = rows
        guard let index = allRows.indexOf(currentRow) else { return nil }
        guard index < allRows.count - 1 else { return nil }
        return allRows[index + 1]
    }
    
    internal func previousRowForRow(currentRow: BaseRow) -> BaseRow? {
        let allRows = rows
        guard let index = allRows.indexOf(currentRow) else { return nil }
        guard index > 0 else { return nil }
        return allRows[index - 1]
    }
    
    private func hideSection(section: Section){
        kvoWrapper.sections.removeObject(section)
    }
    
    private func showSection(section: Section){
        guard !kvoWrapper.sections.containsObject(section) else { return }
        guard var index = kvoWrapper._allSections.indexOf(section) else { return }
        var formIndex = NSNotFound
        while (formIndex == NSNotFound && index > 0){
            let previous = kvoWrapper._allSections[--index]
            formIndex = kvoWrapper.sections.indexOfObject(previous)
        }
        if formIndex == NSNotFound{
            kvoWrapper.sections.insertObject(section, atIndex: 0)
        }
        else{
            kvoWrapper.sections.insertObject(section, atIndex: ++formIndex)
        }
    }
}


// MARK: Section

extension Section : Equatable {}

public func ==(lhs: Section, rhs: Section) -> Bool{
    return lhs === rhs
}

extension Section : Hidable {}

public class Section {

    public var tag: String?
    public private(set) weak var form: Form?
    public var header: HeaderFooterViewRepresentable?
    public var footer: HeaderFooterViewRepresentable?
    
    public var index: Int? { return form?.indexOf(self) }
    
    public var hidden : Condition? {
        willSet { removeFromRowObservers() }
        didSet { addToRowObservers() }
    }
    
    public var isHidden : Bool { return hiddenCache }
    
    public required init(){}
    
    public init(_ initializer: Section -> ()){
        initializer(self)
    }

    public init(_ header: HeaderFooterView<UIView>, _ initializer: Section -> () = { _ in }){
        self.header = header
        initializer(self)
    }
    
    public init(header: HeaderFooterView<UIView>, footer: HeaderFooterView<UIView>, _ initializer: Section -> () = { _ in }){
        self.header = header
        self.footer = footer
        initializer(self)
    }
    
    public init(footer: HeaderFooterView<UIView>, _ initializer: Section -> () = { _ in }){
        self.footer = footer
        initializer(self)
    }
    
    //MARK: Private
    private lazy var kvoWrapper: KVOWrapper = { [unowned self] in return KVOWrapper(section: self) }()
    private var headerView: UIView?
    private var footerView: UIView?
    private var hiddenCache = false
}


extension Section : MutableCollectionType {
    
//MARK: MutableCollectionType
    
    public var startIndex: Int { return 0 }
    public var endIndex: Int { return kvoWrapper.rows.count }
    public subscript (position: Int) -> BaseRow {
        get {
            if position >= kvoWrapper.rows.count{
                assertionFailure("Section: Index out of bounds")
            }
            return kvoWrapper.rows[position] as! BaseRow
        }
        set { kvoWrapper.rows[position] = newValue }
    }
}

extension Section : RangeReplaceableCollectionType {

// MARK: RangeReplaceableCollectionType
    
    public func append(formRow: BaseRow){
        kvoWrapper.rows.insertObject(formRow, atIndex: kvoWrapper.rows.count)
        kvoWrapper._allRows.append(formRow)
        
        formRow.wasAddedToFormInSection(self)
    }
    
    public func appendContentsOf<S : SequenceType where S.Generator.Element == BaseRow>(newElements: S) {
        kvoWrapper.rows.addObjectsFromArray(newElements.map { $0 })
        kvoWrapper._allRows.appendContentsOf(newElements)
        for row in newElements{
            row.wasAddedToFormInSection(self)
        }
    }
    
    public func reserveCapacity(n: Int){}
    
    public func replaceRange<C : CollectionType where C.Generator.Element == BaseRow>(subRange: Range<Int>, with newElements: C) {
        for (var i = subRange.startIndex; i < subRange.endIndex; i++) {
            if let row = kvoWrapper.rows.objectAtIndex(i) as? BaseRow {
                row.willBeRemovedFromForm()
                kvoWrapper._allRows.removeAtIndex(kvoWrapper._allRows.indexOf(row)!)
            }
        }
        kvoWrapper.rows.replaceObjectsInRange(NSMakeRange(subRange.startIndex, subRange.endIndex - subRange.startIndex), withObjectsFromArray: newElements.map { $0 })
        kvoWrapper._allRows.appendContentsOf(newElements)
        for row in newElements{
            row.wasAddedToFormInSection(self)
        }
    }
    
    public func removeAll(keepCapacity keepCapacity: Bool = false) {
        // not doing anything with capacity
        for row in kvoWrapper._allRows{
            row.willBeRemovedFromForm()
        }
        kvoWrapper.rows.removeAllObjects()
        kvoWrapper._allRows.removeAll()
    }
}

public enum HeaderFooterProvider<ViewType: UIView> {
    case Class
    case Callback(()->ViewType)
    case NibFile(name: String, bundle: NSBundle?)
    
    internal func createView() -> ViewType {
        switch self {
            case .Class:
                return ViewType.init()
            case .Callback(let builder):
                return builder()
            case .NibFile(let nibName, let bundle):
                return (bundle ?? NSBundle(forClass: ViewType.self)).loadNibNamed(nibName, owner: nil, options: nil)[0] as! ViewType
        }
    }
}

public enum HeaderFooterType {
    case Header, Footer
}

public struct HeaderFooterView<ViewType: UIView> : StringLiteralConvertible, HeaderFooterViewRepresentable {
    
    public var title: String?
    public var viewProvider: HeaderFooterProvider<ViewType>?
    public var onSetupView: ((view: ViewType, section: Section, form: FormViewController) -> ())?
    public var height: CGFloat?

    lazy internal var staticView : ViewType? = {
        guard let view = self.viewProvider?.createView() else { return nil }
        return view;
    }()
    
    public func viewForSection(section: Section, type: HeaderFooterType, controller: FormViewController) -> UIView? {
        var view: ViewType?
        if type == .Header {
            view = section.headerView as? ViewType
            if view == nil {
                view = viewProvider?.createView()
                section.headerView = view
            }
        }
        else {
            view = section.footerView as? ViewType
            if view == nil {
                view = viewProvider?.createView()
                section.footerView = view
            }
        }
        guard let v = view else { return nil }
        onSetupView?(view: v, section: section, form: controller)
        v.setNeedsUpdateConstraints()
        v.updateConstraintsIfNeeded()
        v.setNeedsLayout()
        v.layoutIfNeeded()
        return v
    }
    
    init?(title: String?){
        guard let t = title else { return nil }
        self.init(stringLiteral: t)
    }
    
    public init(_ provider: HeaderFooterProvider<ViewType>){
        viewProvider = provider
    }
    
    public init(unicodeScalarLiteral value: String) {
        self.title  = value
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.title = value
    }

    public init(stringLiteral value: String) {
        self.title = value
    }
}


extension Section {
    
    private class KVOWrapper : NSObject{
        
        dynamic var _rows = NSMutableArray()
        var rows : NSMutableArray {
            get {
                return mutableArrayValueForKey("_rows")
            }
        }
        private var _allRows = [BaseRow]()
        
        weak var section: Section?
        
        init(section: Section){
            self.section = section
            super.init()
            addObserver(self, forKeyPath: "_rows", options: NSKeyValueObservingOptions.New.union(.Old), context:nil)
        }
        
        deinit{
            removeObserver(self, forKeyPath: "_rows")
        }
        
        override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
            let newRows = change![NSKeyValueChangeNewKey] as? [BaseRow] ?? []
            let oldRows = change![NSKeyValueChangeOldKey] as? [BaseRow] ?? []
            guard let delegateValue = section?.form?.delegate, let keyPathValue = keyPath, let changeType = change?[NSKeyValueChangeKindKey] else{ return }
            guard keyPathValue == "_rows" else { return }
            switch changeType.unsignedLongValue {
                case NSKeyValueChange.Setting.rawValue:
                    delegateValue.rowsHaveBeenAdded(newRows, atIndexPaths:[NSIndexPath(index: 0)])
                case NSKeyValueChange.Insertion.rawValue:
                    let indexSet = change![NSKeyValueChangeIndexesKey] as! NSIndexSet
                    delegateValue.rowsHaveBeenAdded(newRows, atIndexPaths: indexSet.map { NSIndexPath(forRow: $0, inSection: section!.index! ) } )
                case NSKeyValueChange.Removal.rawValue:
                    let indexSet = change![NSKeyValueChangeIndexesKey] as! NSIndexSet
                    delegateValue.rowsHaveBeenRemoved(oldRows, atIndexPaths: indexSet.map { NSIndexPath(forRow: $0, inSection: section!.index! ) } )
                case NSKeyValueChange.Replacement.rawValue:
                    let indexSet = change![NSKeyValueChangeIndexesKey] as! NSIndexSet
                    delegateValue.rowsHaveBeenReplaced(oldRows: oldRows, newRows: newRows, atIndexPaths: indexSet.map { NSIndexPath(forRow: $0, inSection: section!.index!)})
                default:
                    assertionFailure()
            }
        }
    }
    
    public func rowByTag<Row: RowType>(tag: String) -> Row? {
        guard let index = kvoWrapper._allRows.indexOf({ $0.tag == tag }) else { return nil }
        return kvoWrapper._allRows[index] as? Row
    }
}

extension Section /* Condition */{
    
    //MARK: Hidden/Disable Engine
    
    public func evaluateHidden(){
        if let h = hidden, let f = form {
            switch h {
                case .Function(_ , let callback):
                    hiddenCache = callback(f)
                case .Predicate(let predicate):
                    hiddenCache = predicate.evaluateWithObject(self, substitutionVariables: f.dictionaryValuesToEvaluatePredicate())
            }
            if hiddenCache {
                form?.hideSection(self)
            }
            else{
                form?.showSection(self)
            }
        }
    }
    
    func wasAddedToForm(form: Form) {
        self.form = form
        addToRowObservers()
        evaluateHidden()
        for row in kvoWrapper._allRows {
            row.wasAddedToFormInSection(self)
        }
    }
    
    func addToRowObservers(){
        guard let h = hidden else { return }
        switch h {
            case .Function(let tags, _):
                form?.addRowObservers(self, rowTags: tags, type: .Hidden)
            case .Predicate(let predicate):
                form?.addRowObservers(self, rowTags: predicate.predicateVars, type: .Hidden)
        }
    }
    
    func willBeRemovedFromForm(){
        for row in kvoWrapper._allRows {
            row.willBeRemovedFromForm()
        }
        removeFromRowObservers()
        self.form = nil
    }
    
    func removeFromRowObservers(){
        guard let h = hidden else { return }
        switch h {
            case .Function(let tags, _):
                form?.removeRowObservers(self, rows: tags, type: .Hidden)
            case .Predicate(let predicate):
                form?.removeRowObservers(self, rows: predicate.predicateVars, type: .Hidden)
        }
    }
    
    public func hideRow(row: BaseRow){
        kvoWrapper.rows.removeObject(row)
    }
    
    public func showRow(row: BaseRow){
        if kvoWrapper.rows.containsObject(row){
            return
        }
        
        var formIndex = NSNotFound
        
        if var index = kvoWrapper._allRows.indexOf(row){
            while (formIndex == NSNotFound && index > 0){
                let previous = kvoWrapper._allRows[--index]
                formIndex = kvoWrapper.rows.indexOfObject(previous)
            }
            if formIndex == NSNotFound{
                kvoWrapper.rows.insertObject(row, atIndex: 0)
            }
            else{
                kvoWrapper.rows.insertObject(row, atIndex: formIndex+1)
            }
        }
    }
}


// MARK: Row

internal protocol Disableable : Taggable {
    func evaluateDisabled()
    var disabled : Condition? { get set }
    var isDisabled : Bool { get }
}

internal protocol Hidable: Taggable {
    func evaluateHidden()
    var hidden : Condition? { get set }
    var isHidden : Bool { get }
}

extension PresenterRowType {
    public func onPresent(callback: (FormViewController, ProviderType)->()) -> Self {
        onPresentCallback = callback
        return self
    }
}

extension RowType where Cell : TypedCellType, Cell.Value == Self.Value {
    
    public init(_ tag: String? = nil, _ initializer: (Self -> ()) = { _ in }) {
        self.init(tag: tag)
        let callback : Self -> () = RowDefaults.sharedInstance.defaultRowInitializer(self.dynamicType) as! Self -> ()
        callback(self)
        initializer(self)
    }
}


internal class RowDefaults {
    static let sharedInstance = RowDefaults()
    private var cellUpdate = Dictionary<String, Any>()
    private var cellSetup = Dictionary<String, Any>()
    private var rowInitialization = Dictionary<String, Any>()
    
    private static let _defaultCallback: ((BaseCell, BaseRow) -> ()) = { _, _ in }
    private static let _defaultRowCallback: (BaseRow -> ()) = { _ in }
    
    private func defaultCellUpdateForRow(type: Any.Type) -> Any{
        let className = "\(type)"
        return cellUpdate[className] ?? (RowDefaults._defaultCallback as Any)
    }
    
    private func setDefaultCellUpdateForRow(type: Any.Type, callback: Any){
        let className = "\(type)"
        cellUpdate[className] = callback
    }
    
    
    private func defaultCellSetupForRow(type: Any.Type) -> Any{
        let className = "\(type)"
        return cellSetup[className] ?? (RowDefaults._defaultCallback as Any)
    }
    
    private func setDefaultCellSetupForRow(type: Any.Type, callback: Any){
        let className = "\(type)"
        cellSetup[className] = callback
    }
    
    func defaultRowInitializer(type: Any.Type) -> Any{
        let className = "\(type)"
        return rowInitialization[className] ?? (RowDefaults._defaultRowCallback as Any)
    }
    
    private func setDefaultRowInitializer(type: Any.Type, callback: Any){
        let className = "\(type)"
        rowInitialization[className] = callback
    }
}

extension RowType where Cell : TypedCellType, Cell.Value == Value {
    
    public static  var defaultCellUpdate:((Cell, Self) -> ()) {
        set { RowDefaults.sharedInstance.setDefaultCellUpdateForRow(self, callback: newValue) }
        get{ return RowDefaults.sharedInstance.defaultCellUpdateForRow(self) as Any as! ((Cell, Self) -> ()) }
    }
    
    public static var defaultCellSetup:((Cell, Self) -> ()) {
        set { RowDefaults.sharedInstance.setDefaultCellSetupForRow(self, callback: newValue) }
        get{ return RowDefaults.sharedInstance.defaultCellSetupForRow(self) as Any as! ((Cell, Self) -> ()) }
    }
    
    public static var defaultRowInitializer:(Self -> ()) {
        set { RowDefaults.sharedInstance.setDefaultRowInitializer(self, callback: newValue) }
        get { return RowDefaults.sharedInstance.defaultRowInitializer(self) as Any as! (Self -> ()) }
    }
    
    public var cellUpdateCallback: ((Cell, Self) -> ())? {
        return callbackCellUpdate as! ((Cell, Self) -> ())?
    }
    
    public func cellUpdate(callback: ((cell: Cell, row: Self) -> ())) -> Self{
        callbackCellUpdate = callback
        return self
    }
    
    public var cellSetupCallback: ((Cell, Self) -> ())? {
        return callbackCellSetup as! ((Cell, Self) -> ())?
    }
    
    public func cellSetup(callback: ((cell: Cell, row: Self) -> ())) -> Self{
        callbackCellSetup = callback
        return self
    }
    
    public var onChangeCallback: (Self -> ())? {
        return callbackOnChange as! (Self -> ())?
    }
    
    public func onChange(callback: Self -> ()) -> Self{
        callbackOnChange = callback
        return self
    }
    
    public var onCellSelectionCallback: ((Cell, Self) -> ())? {
        return callbackCellOnSelection as! ((Cell, Self) -> ())?
    }

    public func onCellSelection(callback: ((cell: Cell, row: Self) -> ())) -> Self{
        callbackCellOnSelection = callback
        return self
    }
}


public class BaseRow : BaseRowType {

    public var callbackOnChange: Any?
    public var callbackCellUpdate: Any?
    public var callbackCellSetup: Any?
    public var callbackCellOnSelection: Any?
    
    public var title: String?
    public var cellStyle = UITableViewCellStyle.Value1
    public var tag: String?
    public var baseCell: BaseCell! { return nil }
    public var baseValue: Any? {
        set {}
        get { return nil }
    }

    private var hiddenCache = false
    private var disabledCache = false
    public var disabled : Condition? {
        willSet { removeFromDisabledRowObservers() }
        didSet  { addToDisabledRowObservers() }
    }
    public var hidden : Condition? {
        willSet { removeFromHiddenRowObservers() }
        didSet  { addToHiddenRowObservers() }
    }
    public var isDisabled : Bool { return disabledCache }
    public var isHidden : Bool { return hiddenCache }
    
    public weak var section: Section?

    public required init(tag: String? = nil){
        self.tag = tag
    }
    public func updateCell() {}
    public func didSelect() {}
    public func prepareForSegue(segue: UIStoryboardSegue) {}
    
    public final func indexPath() -> NSIndexPath? {
        guard let sectionIndex = section?.index, let rowIndex = section?.indexOf(self) else { return nil }
        return NSIndexPath(forRow: rowIndex, inSection: sectionIndex)
    }

}

extension BaseRow: Equatable, Hidable, Disableable {}

public func ==(lhs: BaseRow, rhs: BaseRow) -> Bool{
    return lhs === rhs
}

extension BaseRow {
    
    public final func evaluateHidden() {
        guard let h = hidden, let form = section?.form else { return }
        switch h {
            case .Function(_ , let callback):
                hiddenCache = callback(form)
            case .Predicate(let predicate):
                hiddenCache = predicate.evaluateWithObject(self, substitutionVariables: form.dictionaryValuesToEvaluatePredicate())
        }
        if hiddenCache {
            baseCell.resignFirstResponder()
            section?.hideRow(self)
        }
        else{
            section?.showRow(self)
        }
    }
    
    public final func evaluateDisabled() {
        guard let d = disabled, form = section?.form else { return }
        switch d {
            case .Function(_ , let callback):
                disabledCache = callback(form)
            case .Predicate(let predicate):
                disabledCache = predicate.evaluateWithObject(self, substitutionVariables: form.dictionaryValuesToEvaluatePredicate())
        }
        updateCell()
    }
    
    private final func wasAddedToFormInSection(section: Section) {
        self.section = section
        if let t = tag {
            assert(section.form?.rowsByTag[t] == nil, "Duplicate tag \(t)")
            self.section?.form?.rowsByTag[t] = self
        }
        addToRowObservers()
        evaluateHidden()
        evaluateDisabled()
    }
    
    private final func addToHiddenRowObservers() {
        guard let h = hidden else { return }
        switch h {
            case .Function(let tags, _):
                section?.form?.addRowObservers(self, rowTags: tags, type: .Hidden)
            case .Predicate(let predicate):
                section?.form?.addRowObservers(self, rowTags: predicate.predicateVars, type: .Hidden)
        }
    }
    
    private final func addToDisabledRowObservers() {
        guard let d = disabled else { return }
        switch d {
            case .Function(let tags, _):
                section?.form?.addRowObservers(self, rowTags: tags, type: .Disabled)
            case .Predicate(let predicate):
                section?.form?.addRowObservers(self, rowTags: predicate.predicateVars, type: .Disabled)
        }
    }
    
    private final func addToRowObservers(){
        addToHiddenRowObservers()
        addToDisabledRowObservers()
    }
    
    private final func willBeRemovedFromForm(){
        if let t = tag {
            self.section?.form?.rowsByTag[t] = nil
        }
        removeFromRowObservers()
    }
    
    
    private final func removeFromHiddenRowObservers() {
        guard let h = hidden else { return }
        switch h {
            case .Function(let tags, _):
                section?.form?.removeRowObservers(self, rows: tags, type: .Hidden)
            case .Predicate(let predicate):
                section?.form?.removeRowObservers(self, rows: predicate.predicateVars, type: .Hidden)
        }
    }
    
    private final func removeFromDisabledRowObservers() {
        guard let d = disabled else { return }
        switch d {
            case .Function(let tags, _):
                section?.form?.removeRowObservers(self, rows: tags, type: .Disabled)
            case .Predicate(let predicate):
                section?.form?.removeRowObservers(self, rows: predicate.predicateVars, type: .Disabled)
        }
    }
    
    
    private final func removeFromRowObservers(){
        removeFromHiddenRowObservers()
        removeFromDisabledRowObservers()
    }
}

public class RowOf<T: Equatable>: BaseRow {
    
    public var value : T?{
        didSet {
            guard value != oldValue else { return }
            guard let form = section?.form else { return }
            if let delegate = form.delegate {
                delegate.rowValueHasBeenChanged(self, oldValue: oldValue, newValue: value)
                if let callback = callbackOnChange{
                    (callback as! ((RowOf<T>) -> ()))(self)
                }
            }
            guard let t = tag else { return }
            if let rowObservers = form.rowObservers[t]?[.Hidden]{
                for rowObserver in rowObservers {
                    (rowObserver as? Hidable)?.evaluateHidden()
                }
            }
            if let rowObservers = form.rowObservers[t]?[.Disabled]{
                for rowObserver in rowObservers {
                    (rowObserver as? Disableable)?.evaluateDisabled()
                }
            }
        }
    }
    
    public override var baseValue: Any? {
        get { return value }
        set { value = newValue as? T }
    }
    
    public var dataProvider: DataProvider<T>?
        
    public var displayValueFor : (T? -> String?)? = {
        if let t = $0 {
            return String(t)
        }
        return nil
    }
    
    public required init(tag: String?){
        super.init(tag: tag)
    }
    
}


public class Row<T: Equatable, Cell: CellType where Cell: BaseCell, Cell.Value == T>: RowOf<T>,  TypedRowType {
    
    public var cellProvider = CellProvider<Cell>()
    public let cellType: Cell.Type! = Cell.self
    public lazy var cell : Cell! = {
        [unowned self] in
        
        let result = self.cellProvider.createCell(self.cellStyle)
        
        result.row = self
        result.setup()
        let callback : ((Cell, Row<T, Cell>) -> ()) = (RowDefaults.sharedInstance.defaultCellSetupForRow(self.dynamicType) as! (((Cell, Row<T, Cell>) -> ())))
        callback(result, self)
        if let callback = self.callbackCellSetup{
            (callback as! ((Cell, Row<T, Cell>) -> ()))(result, self)
        }
        return result
    }()
    
    public override var baseCell: BaseCell! { return cell! }

    public required init(tag: String?) {
        super.init(tag: tag)
    }

    override public func updateCell() {
        super.updateCell()
        cell?.row = self
        cell?.update()
        customUpdateCell()
        let callback : ((Cell, Row<T, Cell>) -> ()) = (RowDefaults.sharedInstance.defaultCellUpdateForRow(self.dynamicType) as! (((Cell, Row<T, Cell>) -> ())))
        callback(cell!, self)
        if let callback = callbackCellUpdate{
            (callback as! ((Cell, Row<T, Cell>) -> ()))(cell!, self)
        }
        cell?.setNeedsLayout()
        cell?.setNeedsUpdateConstraints()
    }
    
    public override func didSelect() {
        super.didSelect()
        if !isDisabled {
            cell?.didSelect()
        }
        customDidSelect()
        if let callback = callbackCellOnSelection {
            (callback as! ((Cell, Row<T, Cell>) -> ()))(cell!, self)
        }
    }
    
    public func customDidSelect(){}
    
    public func customUpdateCell(){}
    
}

// MARK: Operators

infix operator +++{ associativity left precedence 95 }

public func +++(left: Form, right: Section) -> Form {
    left.append(right)
    return left
}

infix operator +++= { associativity left precedence 95 }

public func +++=(inout left: Form, right: Section){
    left = left +++ right
}

public func +++=(inout left: Form, right: BaseRow){
    left +++= Section() <<< right
}

public func +++(left: Section, right: Section) -> Form {
    let form = Form()
    form +++ left +++ right
    return form
}

public func +++(left: BaseRow, right: BaseRow) -> Form {
    let form = Section() <<< left +++ Section() <<< right
    return form
}

infix operator <<<{ associativity left precedence 100 }

public func <<<(left: Section, right: BaseRow) -> Section {
    left.append(right)
    return left
}

public func <<<(left: BaseRow, right: BaseRow) -> Section {
    let section = Section()
    section <<< left <<< right
    return section
}


public func +=< C : CollectionType where C.Generator.Element == BaseRow>(inout lhs: Section, rhs: C){
    lhs.appendContentsOf(rhs)
}

public func +=< C : CollectionType where C.Generator.Element == Section>(inout lhs: Form, rhs: C){
    lhs.appendContentsOf(rhs)
}

// MARK: FormCells

public protocol TextFieldCell {
    var textField : UITextField { get }
}

extension CellType where Self: UITableViewCell {
}

public class BaseCell : UITableViewCell, BaseCellType {
    
    public var height: (()->CGFloat)?
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public required override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    
    public func formViewController () -> FormViewController? {
        var responder : AnyObject? = self
        while responder != nil {
            if responder! is FormViewController {
                return responder as? FormViewController
            }
            responder = responder?.nextResponder()
        }
        return nil
    }
    
    public func setup(){}
    public func update() {}
    
    public func didSelect() {}
    
    public func highlight() {}
    public func unhighlight() {}
    
    
    public func cellCanBecomeFirstResponder() -> Bool {
        return false
    }
    
    public func cellBecomeFirstResponder() -> Bool {
        return becomeFirstResponder()
    }

}


public class Cell<T: Equatable> : BaseCell, TypedCellType {
    
    public typealias Value = T
    
    public var row : RowOf<T>!
    
    override public var inputAccessoryView: UIView? {
        if let v = formViewController()?.inputAccessoryViewForRow(row){
            return v
        }
        return super.inputAccessoryView
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    required public init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    
    public override func setup(){
        super.setup()
    }
    
    public override func update(){
        super.update()
        textLabel?.text = row.title
        textLabel?.textColor = row.isDisabled ? .grayColor() : .blackColor()
        detailTextLabel?.text = row.displayValueFor?(row.value)
    }
    
    public override func didSelect() {}
    
    private var _titleColor: UIColor! = .blackColor()
    public override func highlight(){
        super.highlight()
        _titleColor = textLabel?.textColor
        textLabel?.textColor = tintColor
    }
    
    public override func unhighlight(){
        super.unhighlight()
        textLabel?.textColor = _titleColor
        row.updateCell()
    }
    
    public override func canBecomeFirstResponder() -> Bool {
        return false
    }
    
    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            formViewController()?.beginEditing(self)
        }
        return result
    }
    
    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            formViewController()?.endEditing(self)
        }
        return result
    }
    
}

public struct CellProvider<Cell: BaseCell where Cell: CellType> {
    
    public private (set) var nibName: String?
    public private(set) var bundle: NSBundle!

    
    public init(){}
    
    public init(nibName: String, bundle: NSBundle? = nil){
        self.nibName = nibName
        self.bundle = bundle ?? NSBundle(forClass: Cell.self)
    }
    
    func createCell(cellStyle: UITableViewCellStyle) -> Cell {
        if let nibName = self.nibName {
            return bundle.loadNibNamed(nibName, owner: nil, options: nil).first as! Cell
        }
        return Cell.init(style: cellStyle, reuseIdentifier: nil)
    }
}

public enum ControllerProvider<VCType: UIViewController>{
    case Callback(builder: (() -> VCType))
    case NibFile(name: String, bundle: NSBundle?)
    case StoryBoard(storyboardId: String, storyboardName: String, bundle: NSBundle?)
    
    func createController() -> VCType {
        switch self {
            case .Callback(let builder):
                return builder()
            case .NibFile(let nibName, let bundle):
                return VCType.init(nibName: nibName, bundle:bundle ?? NSBundle(forClass: VCType.self))
            case .StoryBoard(let storyboardId, let storyboardName, let bundle):
                let sb = UIStoryboard(name: storyboardName, bundle: bundle ?? NSBundle(forClass: VCType.self))
                return sb.instantiateViewControllerWithIdentifier(storyboardId) as! VCType
        }
    }
}

public struct DataProvider<T: Equatable> {
    
    internal var arrayData: [T]?
    
    init(arrayData: [T]){
        self.arrayData = arrayData
    }
}

public enum PresentationMode<VCType: UIViewController> {
    
    case Show(controllerProvider: ControllerProvider<VCType>, completionCallback: (UIViewController->())?)
    case PresentModally(controllerProvider: ControllerProvider<VCType>, completionCallback: (UIViewController->())?)
    case SegueName(segueName: String, completionCallback: (UIViewController->())?)
    case SegueClass(segueClass: UIStoryboardSegue.Type, completionCallback: (UIViewController->())?)
    
    
    var completionHandler: (UIViewController ->())? {
        switch self{
            case .Show(_, let completionCallback):
                return completionCallback
            case .PresentModally(_, let completionCallback):
                return completionCallback
            case .SegueName(_, let completionCallback):
                return completionCallback
            case .SegueClass(_, let completionCallback):
                return completionCallback
        }
    }
    
    func presentViewController(viewController: VCType!, row: BaseRow, presentingViewController:FormViewController){
        switch self {
            case .Show(_, _):
                presentingViewController.showViewController(viewController, sender: row)
            case .PresentModally:
                presentingViewController.presentViewController(viewController, animated: true, completion: nil)
            case .SegueName(let segueName, _):
                presentingViewController.performSegueWithIdentifier(segueName, sender: row)
            case .SegueClass(let segueClass, _):
                let segue = segueClass.init(identifier: row.tag, source: presentingViewController, destination: viewController)
                presentingViewController.prepareForSegue(segue, sender: row)
                segue.perform()
        }
        
    }
    
    func createController() -> VCType? {
        switch self {
            case .Show(let controllerProvider, let completionCallback):
                let controller = controllerProvider.createController()
                let completionController = controller as? RowControllerType
                if let callback = completionCallback {
                    completionController?.completionCallback = callback
                }
                return controller
            case .PresentModally(let controllerProvider, let completionCallback):
                let controller = controllerProvider.createController()
                let completionController = controller as? RowControllerType
                if let callback = completionCallback {
                    completionController?.completionCallback = callback
                }
                return controller
            default:
                return nil;
        }
    }
}

public protocol FormatterProtocol{
    func getNewPosition(forPosition forPosition: UITextPosition, inTextField: UITextField, oldValue: String?, newValue: String?) -> UITextPosition
}

//MARK: Predicate Machine

internal enum ConditionType {
    case Hidden, Disabled
}

public enum Condition {
    case Function([String], Form->Bool)
    case Predicate(NSPredicate)
}

extension Condition : BooleanLiteralConvertible {
    
    public init(booleanLiteral value: Bool){
        self = Condition.Function([]) { _ in return value }
    }
}

extension Condition : StringLiteralConvertible {
    
    public init(stringLiteral value: String){
        self = .Predicate(NSPredicate(format: value))
    }
    
    public init(unicodeScalarLiteral value: String) {
        self = .Predicate(NSPredicate(format: value))
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        self = .Predicate(NSPredicate(format: value))
    }
}
//MARK: Errors

public enum EurekaError : ErrorType {
    case DuplicatedTag(tag: String)
}


//Mark: FormViewController

public protocol FormViewControllerProtocol {
    func beginEditing<T:Equatable>(cell: Cell<T>)
    func endEditing<T:Equatable>(cell: Cell<T>)
    
    func insertAnimationForRows(rows: [BaseRow]) -> UITableViewRowAnimation
    func deleteAnimationForRows(rows: [BaseRow]) -> UITableViewRowAnimation
    func reloadAnimationOldRows(oldRows: [BaseRow], newRows: [BaseRow]) -> UITableViewRowAnimation
    func insertAnimationForSections(sections : [Section]) -> UITableViewRowAnimation
    func deleteAnimationForSections(sections : [Section]) -> UITableViewRowAnimation
    func reloadAnimationOldSections(oldSections: [Section], newSections:[Section]) -> UITableViewRowAnimation
}

public struct RowNavigationOptions : OptionSetType {
    
    private enum NavigationOptions : Int {
        case None = 1, Enabled = 2, StopDisabledRow = 4, SkipCanNotBecomeFirstResponderRow = 8
    }
    public let rawValue: Int
    public  init(rawValue: Int){ self.rawValue = rawValue}
    private init(_ options:NavigationOptions ){ self.rawValue = options.rawValue }
    
    public static let None = RowNavigationOptions(.None)
    public static let Enabled = RowNavigationOptions(.Enabled)
    public static let StopDisabledRow = RowNavigationOptions(.StopDisabledRow)
    public static let SkipCanNotBecomeFirstResponderRow = RowNavigationOptions(.SkipCanNotBecomeFirstResponderRow)
}


public class FormViewController : UIViewController {
    
    @IBOutlet public var tableView: UITableView?
    
    private lazy var _form : Form = { [unowned self] in
        let form = Form()
        form.delegate = self
        return form
        }()
    public var form : Form {
        get { return _form }
        set {
            _form.delegate = nil
            tableView?.endEditing(false)
            _form = newValue
            _form.delegate = self;
            if isViewLoaded() && tableView?.window != nil {
                tableView?.reloadData()
            }
        }
    }
    
    lazy public var navigationAccessoryView : NavigationAccessoryView = {
        [unowned self] in
        let naview = NavigationAccessoryView(frame: CGRectMake(0, 0, self.view.frame.width, 44.0))
        naview.doneButton.target = self
        naview.doneButton.action = "navigationDone:"
        naview.previousButton.target = self
        naview.previousButton.action = "navigationAction:"
        naview.nextButton.target = self
        naview.nextButton.action = "navigationAction:"
        naview.tintColor = self.view.tintColor
        return naview
        }()
    
    public var navigationOptions : RowNavigationOptions?
    
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        if tableView == nil {
            tableView = UITableView(frame: view.bounds, style: .Grouped)
            tableView?.autoresizingMask = UIViewAutoresizing.FlexibleWidth.union(.FlexibleHeight)
        }
        if tableView?.superview == nil {
            view.addSubview(tableView!)
        }
        if tableView?.delegate == nil {
            tableView?.delegate = self
        }
        if tableView?.dataSource == nil {
            tableView?.dataSource = self
        }
        tableView?.rowHeight = UITableViewAutomaticDimension
        tableView?.estimatedRowHeight = 44.0
    }
    
    public override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        if let selectedIndexPath = tableView?.indexPathForSelectedRow {
            tableView?.reloadRowsAtIndexPaths([selectedIndexPath], withRowAnimation: .None)
            tableView?.selectRowAtIndexPath(selectedIndexPath, animated: false, scrollPosition: .None)
            tableView?.deselectRowAtIndexPath(selectedIndexPath, animated: true)
        }
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillShow:", name: UIKeyboardWillShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillHide:", name: UIKeyboardWillHideNotification, object: nil)
    }
    
    public override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillShowNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillHideNotification, object: nil)
    }
    
    public override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
        let baseRow = sender as? BaseRow
        baseRow?.prepareForSegue(segue)
    }
    
    //MARK: Private
    
    private var oldBottomInset : CGFloat = 0.0
}

extension FormViewController : UITableViewDelegate {
    
    //MARK: UITableViewDelegate
    
    public func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        guard tableView == self.tableView else { return }
        form[indexPath].updateCell()
    }
    
    public func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        return indexPath
    }
    
    public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        guard tableView == self.tableView else { return }
        self.tableView?.endEditing(false)
        if !form[indexPath].baseCell.cellCanBecomeFirstResponder() || !form[indexPath].baseCell.cellBecomeFirstResponder() {
            self.tableView?.endEditing(true)
        }
        form[indexPath].didSelect()
    }
    
    public func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        guard tableView == self.tableView else { return tableView.rowHeight }
        let row = form[indexPath.section][indexPath.row]
        return row.baseCell.height?() ?? tableView.rowHeight
    }
    
    public func tableView(tableView: UITableView, estimatedHeightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        guard tableView == self.tableView else { return tableView.rowHeight }
        let row = form[indexPath.section][indexPath.row]
        return row.baseCell.height?() ?? tableView.estimatedRowHeight
    }
    
    public func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return form[section].header?.viewForSection(form[section], type: .Header, controller: self)
    }
    
    public func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return form[section].footer?.viewForSection(form[section], type:.Footer, controller: self)
    }
    
    public func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if let height = form[section].header?.height {
            return height
        }
        guard let view = form[section].header?.viewForSection(form[section], type: .Header, controller: self) else{
            return UITableViewAutomaticDimension
        }
        guard view.bounds.height != 0 else {
            return UITableViewAutomaticDimension
        }
        return view.bounds.height
    }
    
    public func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if let height = form[section].footer?.height {
            return height
        }
        guard let view = form[section].footer?.viewForSection(form[section], type: .Footer, controller: self) else{
            return UITableViewAutomaticDimension
        }
        guard view.bounds.height != 0 else {
            return UITableViewAutomaticDimension
        }
        return view.bounds.height
    }
}

extension FormViewController : UITableViewDataSource {
    
    //MARK: UITableViewDataSource
    
    public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return form.count
    }
    
    public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return form[section].count
    }
    
    public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        return form[indexPath].baseCell
    }
    
    public func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return form[section].header?.title
    }
    
    public func tableView(tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return form[section].footer?.title
    }
    
    public func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return false
    }
    
    public func tableView(tableView: UITableView, canMoveRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return false
    }
    
    public func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
    }
    
    public func tableView(tableView: UITableView, moveRowAtIndexPath sourceIndexPath: NSIndexPath, toIndexPath destinationIndexPath: NSIndexPath) {
    }
}

extension FormViewController : FormDelegate {
    
    //MARK: FormDelegate
    
    public func sectionsHaveBeenAdded(sections: [Section], atIndexes: NSIndexSet){
        tableView?.beginUpdates()
        tableView?.insertSections(atIndexes, withRowAnimation: insertAnimationForSections(sections))
        tableView?.endUpdates()
    }
    
    public func sectionsHaveBeenRemoved(sections: [Section], atIndexes: NSIndexSet){
        tableView?.beginUpdates()
        tableView?.deleteSections(atIndexes, withRowAnimation: deleteAnimationForSections(sections))
        tableView?.endUpdates()
    }
    
    public func sectionsHaveBeenReplaced(oldSections oldSections:[Section], newSections: [Section], atIndexes: NSIndexSet){
        tableView?.beginUpdates()
        tableView?.reloadSections(atIndexes, withRowAnimation: reloadAnimationOldSections(oldSections, newSections: newSections))
        tableView?.endUpdates()
    }
    
    public func rowsHaveBeenAdded(rows: [BaseRow], atIndexPaths: [NSIndexPath]) {
        tableView?.beginUpdates()
        tableView?.insertRowsAtIndexPaths(atIndexPaths, withRowAnimation: insertAnimationForRows(rows))
        tableView?.endUpdates()
    }
    
    public func rowsHaveBeenRemoved(rows: [BaseRow], atIndexPaths: [NSIndexPath]) {
        tableView?.beginUpdates()
        tableView?.deleteRowsAtIndexPaths(atIndexPaths, withRowAnimation: deleteAnimationForRows(rows))
        tableView?.endUpdates()
    }

    
    
    public func rowsHaveBeenReplaced(oldRows oldRows:[BaseRow], newRows: [BaseRow], atIndexPaths: [NSIndexPath]){
        tableView?.beginUpdates()
        tableView?.reloadRowsAtIndexPaths(atIndexPaths, withRowAnimation: reloadAnimationOldRows(oldRows, newRows: newRows))
        tableView?.endUpdates()
    }
    
    public func rowValueHasBeenChanged(row: BaseRow, oldValue: Any, newValue: Any) {}
}

extension FormViewController : UIScrollViewDelegate {
    
    //MARK: UIScrollViewDelegate
    
    public func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        tableView?.endEditing(true)
    }
}

extension FormViewController : FormViewControllerProtocol {
    
    //MARK: FormViewControllerProtocol
    
    public func beginEditing<T:Equatable>(cell: Cell<T>) {
        cell.highlight()
    }
    
    public func endEditing<T:Equatable>(cell: Cell<T>) {
        cell.unhighlight()
    }
    
    public func insertAnimationForRows(rows: [BaseRow]) -> UITableViewRowAnimation {
        return .Fade
    }
    
    public func deleteAnimationForRows(rows: [BaseRow]) -> UITableViewRowAnimation {
        return .Fade
    }
    
    public func reloadAnimationOldRows(oldRows: [BaseRow], newRows: [BaseRow]) -> UITableViewRowAnimation {
        return .Automatic
    }
    
    public func insertAnimationForSections(sections: [Section]) -> UITableViewRowAnimation {
        return .Automatic
    }
    
    public func deleteAnimationForSections(sections: [Section]) -> UITableViewRowAnimation {
        return .Automatic
    }
    
    public func reloadAnimationOldSections(oldSections: [Section], newSections: [Section]) -> UITableViewRowAnimation {
        return .Automatic
    }
}

extension FormViewController {
    
    //MARK: KeyBoard Notifications
    
    public func keyboardWillShow(notification: NSNotification){
        guard let table = tableView, let cell = table.findFirstResponder()?.formCell() else { return }
        let keyBoardInfo = notification.userInfo!
        let keyBoardFrame = table.window!.convertRect((keyBoardInfo[UIKeyboardFrameEndUserInfoKey]?.CGRectValue)!, toView: table.superview)
        let newBottomInset = table.frame.origin.y + table.frame.size.height - keyBoardFrame.origin.y
        var tableInsets = table.contentInset
        var scrollIndicatorInsets = table.scrollIndicatorInsets
        oldBottomInset = oldBottomInset != 0.0 ? oldBottomInset : tableInsets.bottom
        if newBottomInset > oldBottomInset {
            tableInsets.bottom = newBottomInset
            scrollIndicatorInsets.bottom = tableInsets.bottom
            UIView.beginAnimations(nil, context: nil)
            UIView.setAnimationDuration(keyBoardInfo[UIKeyboardAnimationDurationUserInfoKey]!.doubleValue)
            UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: keyBoardInfo[UIKeyboardAnimationCurveUserInfoKey]!.integerValue)!)
            table.contentInset = tableInsets
            table.scrollIndicatorInsets = scrollIndicatorInsets
            if let selectedRow = table.indexPathForCell(cell) {
                table.scrollToRowAtIndexPath(selectedRow, atScrollPosition: .None, animated: false)
            }
            UIView.commitAnimations()
        }
    }
    
    public func keyboardWillHide(notification: NSNotification){
        guard let table = tableView,  let _ = table.findFirstResponder()?.formCell() else  { return }
        let keyBoardInfo = notification.userInfo!
        var tableInsets = table.contentInset
        var scrollIndicatorInsets = table.scrollIndicatorInsets
        tableInsets.bottom = oldBottomInset
        scrollIndicatorInsets.bottom = oldBottomInset
        oldBottomInset = 0.0
        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationDuration(keyBoardInfo[UIKeyboardAnimationDurationUserInfoKey]!.doubleValue)
        UIView.setAnimationCurve(UIViewAnimationCurve(rawValue: keyBoardInfo[UIKeyboardAnimationCurveUserInfoKey]!.integerValue)!)
        table.contentInset = tableInsets
        table.scrollIndicatorInsets = scrollIndicatorInsets
        UIView.commitAnimations()
    }
}

extension FormViewController {
    
    //MARK: Navigation Methods
    
    private enum Direction { case Up, Down }
    
    func navigationDone(sender: UIBarButtonItem) {
        tableView?.endEditing(true)
    }
    
    func navigationAction(sender: UIBarButtonItem) {
        navigateToDirection(sender == navigationAccessoryView.previousButton ? .Up : .Down)
    }
    
    private func navigateToDirection(direction: Direction){
        guard let currentCell = tableView?.findFirstResponder()?.formCell() else { return }
        guard let currentIndexPath = tableView?.indexPathForCell(currentCell) else { assertionFailure(); return }
        guard let nextRow = nextRowForRow(form[currentIndexPath], withDirection: direction) else { return }
        if nextRow.baseCell.cellCanBecomeFirstResponder(){
            tableView?.scrollToRowAtIndexPath(nextRow.indexPath()!, atScrollPosition: .None, animated: false)
            nextRow.baseCell.cellBecomeFirstResponder()
        }
    }
    
    private func nextRowForRow(currentRow: BaseRow, withDirection direction: Direction) -> BaseRow? {
        
        let options = navigationOptions ?? Form.defaultNavigationOptions
        guard options.contains(.Enabled) else { return nil }
        guard let nextRow = direction == .Down ? form.nextRowForRow(currentRow) : form.previousRowForRow(currentRow) else { return nil }
        if nextRow.isDisabled && options.contains(.StopDisabledRow) {
            return nil
        }
        if !nextRow.baseCell.cellCanBecomeFirstResponder() && !nextRow.isDisabled && !options.contains(.SkipCanNotBecomeFirstResponderRow){
            return nil
        }
        if (!nextRow.isDisabled && nextRow.baseCell.cellCanBecomeFirstResponder()){
            return nextRow
        }
        return nextRowForRow(nextRow, withDirection:direction)
    }
    
    public func inputAccessoryViewForRow(row: BaseRow) -> UIView? {
        let options = navigationOptions ?? Form.defaultNavigationOptions
        guard options.contains(.Enabled) else { return nil }
        guard row.baseCell.cellCanBecomeFirstResponder() else { return nil}
        navigationAccessoryView.previousButton.enabled = nextRowForRow(row, withDirection: .Up) != nil
        navigationAccessoryView.nextButton.enabled = nextRowForRow(row, withDirection: .Down) != nil
        return navigationAccessoryView
    }
}

public class NavigationAccessoryView : UIToolbar {
    
    public var previousButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem(rawValue: 105)!, target: nil, action: nil)
    public var nextButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem(rawValue: 106)!, target: nil, action: nil)
    public var doneButton = UIBarButtonItem(barButtonSystemItem: .Done, target: nil, action: nil)
    private var fixedSpace = UIBarButtonItem(barButtonSystemItem: .FixedSpace, target: nil, action: nil)
    private var flexibleSpace = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
    
    override init(frame: CGRect) {
        super.init(frame: CGRectMake(0, 0, frame.size.width, 44.0))
        autoresizingMask = .FlexibleWidth
        fixedSpace.width = 22.0
        setItems([previousButton, fixedSpace, nextButton, flexibleSpace, doneButton], animated: false)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {}
}

